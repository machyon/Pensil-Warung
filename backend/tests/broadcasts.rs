mod common;

use axum::http::StatusCode;
use common::TestApp;
use serde_json::{Value, json};
use time::format_description::well_known::Rfc3339;
use time::{Duration, OffsetDateTime};

const FEED: &str = "/api/v1/broadcasts";
const BC: &str = "/api/v1/broadcaster/broadcasts";

/// Registers a user, makes it a broadcaster in SQL and logs in for a token with the new role.
async fn broadcaster(app: &TestApp, email: &str) -> String {
    app.register("Admin", email, "password123").await;
    app.client()
        .await
        .execute("UPDATE users SET role_id = 2 WHERE email = $1", &[&email])
        .await
        .unwrap();
    let res = app
        .post_json(
            "/api/v1/auth/login",
            None,
            &json!({"email": email, "password": "password123"}),
        )
        .await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    res.json["token"].as_str().unwrap().to_owned()
}

fn in_minutes(m: i64) -> String {
    (OffsetDateTime::now_utc() + Duration::minutes(m))
        .format(&Rfc3339)
        .unwrap()
}

async fn make(app: &TestApp, token: &str, title: &str, send_at: Value) -> Value {
    let body = json!({"category": "info", "title": title, "summary": "ringkas", "body": "isi", "send_at": send_at});
    let res = app.post_json(BC, Some(token), &body).await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    res.json
}

/// Moves a scheduled broadcast's time into the past, as if it came due.
async fn make_due(app: &TestApp, id: &Value) {
    app.client()
        .await
        .execute(
            "UPDATE broadcasts SET scheduled_for = now() - interval '1 minute' WHERE id = $1",
            &[&(id.as_i64().unwrap() as i32)],
        )
        .await
        .unwrap();
}

fn titles(v: &Value) -> Vec<&str> {
    v.as_array()
        .unwrap()
        .iter()
        .map(|b| b["title"].as_str().unwrap())
        .collect()
}

#[tokio::test]
async fn feed_shows_sent_and_due_but_not_future_or_cancelled() {
    let app = TestApp::new().await;
    let b = broadcaster(&app, "a@example.com").await;
    let user = app
        .register("Siti", "siti@example.com", "password123")
        .await;

    make(&app, &b, "sent", json!(null)).await;
    let future = make(&app, &b, "future", json!(in_minutes(60))).await;
    let due = make(&app, &b, "due", json!(in_minutes(60))).await;
    let cancelled = make(&app, &b, "cancelled", json!(in_minutes(60))).await;
    let path = format!("{BC}/{}/cancel", cancelled["id"]);
    assert_eq!(
        app.post_json(&path, Some(&b), &json!({})).await.status,
        StatusCode::OK
    );
    make_due(&app, &due["id"]).await;

    let res = app.get(FEED, Some(&user)).await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    assert_eq!(titles(&res.json), ["sent", "due"]);
    assert!(res.json[1]["shown_at"].is_string());
    assert_eq!(res.json[0]["has_body"], true);
    assert!(res.json[0].get("body").is_none());

    let detail = app.get(&format!("{FEED}/{}", due["id"]), Some(&user)).await;
    assert_eq!(detail.status, StatusCode::OK);
    assert_eq!(detail.json["body"], "isi");
    for hidden in [&future, &cancelled] {
        let res = app
            .get(&format!("{FEED}/{}", hidden["id"]), Some(&user))
            .await;
        assert_eq!(res.status, StatusCode::NOT_FOUND);
    }
}

#[tokio::test]
async fn feed_is_latest_five() {
    let app = TestApp::new().await;
    let b = broadcaster(&app, "a@example.com").await;
    for i in 0..7 {
        make(&app, &b, &format!("n{i}"), json!(null)).await;
    }
    let res = app.get(FEED, Some(&b)).await;
    assert_eq!(titles(&res.json), ["n6", "n5", "n4", "n3", "n2"]);
}

#[tokio::test]
async fn edit_and_cancel_after_due_are_rejected() {
    let app = TestApp::new().await;
    let b = broadcaster(&app, "a@example.com").await;
    let made = make(&app, &b, "soon", json!(in_minutes(60))).await;
    let id = &made["id"];
    make_due(&app, id).await;

    let res = app
        .patch_json(&format!("{BC}/{id}"), Some(&b), &json!({"title": "x"}))
        .await;
    assert_eq!(res.status, StatusCode::CONFLICT);
    assert_eq!(res.json["error"]["code"], "not_editable");
    let res = app
        .post_json(&format!("{BC}/{id}/cancel"), Some(&b), &json!({}))
        .await;
    assert_eq!(res.status, StatusCode::CONFLICT);

    // Sent now and cancelled ones cannot be changed either; unknown ids are 404.
    let sent = make(&app, &b, "sent", json!(null)).await;
    let res = app
        .patch_json(
            &format!("{BC}/{}", sent["id"]),
            Some(&b),
            &json!({"title": "x"}),
        )
        .await;
    assert_eq!(res.status, StatusCode::CONFLICT);
    let res = app
        .patch_json(&format!("{BC}/9999"), Some(&b), &json!({"title": "x"}))
        .await;
    assert_eq!(res.status, StatusCode::NOT_FOUND);
    let res = app
        .post_json(&format!("{BC}/9999/cancel"), Some(&b), &json!({}))
        .await;
    assert_eq!(res.status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn patch_reschedules_sends_now_and_validates() {
    let app = TestApp::new().await;
    let b = broadcaster(&app, "a@example.com").await;
    let other = broadcaster(&app, "b@example.com").await;
    let made = make(&app, &b, "old", json!(in_minutes(60))).await;
    let path = format!("{BC}/{}", made["id"]);

    // Missing send_at keeps the schedule; another broadcaster may edit it.
    let res = app
        .patch_json(
            &path,
            Some(&other),
            &json!({"title": " new ", "body": "  "}),
        )
        .await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    assert_eq!(res.json["title"], "new");
    assert_eq!(res.json["has_body"], false);
    assert_eq!(res.json["effective_status"], "scheduled");
    assert_eq!(res.json["shown_at"], made["shown_at"]);

    let later = in_minutes(120);
    let res = app
        .patch_json(&path, Some(&b), &json!({"send_at": later}))
        .await;
    assert_eq!(res.json["effective_status"], "scheduled");
    assert_ne!(res.json["shown_at"], made["shown_at"]);

    let past = in_minutes(-5);
    let res = app
        .patch_json(&path, Some(&b), &json!({"send_at": past}))
        .await;
    assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(res.json["error"]["code"], "time_passed");
    let res = app.patch_json(&path, Some(&b), &json!({})).await;
    assert_eq!(res.json["error"]["code"], "nothing_to_update");
    let res = app
        .patch_json(&path, Some(&b), &json!({"category": "x"}))
        .await;
    assert_eq!(res.json["error"]["code"], "invalid_value");

    let res = app
        .patch_json(
            &path,
            Some(&b),
            &json!({"summary": "baru", "send_at": null}),
        )
        .await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    assert_eq!(res.json["effective_status"], "sent");
    assert_eq!(res.json["summary"], "baru");
    let row = app
        .client()
        .await
        .query_one(
            "SELECT status::text, scheduled_for IS NOT NULL, broadcasted_at IS NOT NULL
               FROM broadcasts WHERE id = $1",
            &[&(made["id"].as_i64().unwrap() as i32)],
        )
        .await
        .unwrap();
    assert_eq!(row.get::<_, String>(0), "sent");
    assert!(row.get::<_, bool>(1) && row.get::<_, bool>(2));
    // Now it is in the feed and no longer editable.
    assert_eq!(titles(&app.get(FEED, Some(&b)).await.json), ["new"]);
    let res = app
        .patch_json(&path, Some(&b), &json!({"title": "y"}))
        .await;
    assert_eq!(res.status, StatusCode::CONFLICT);
}

#[tokio::test]
async fn create_validates_and_records_creator() {
    let app = TestApp::new().await;
    let b = broadcaster(&app, "a@example.com").await;
    let ok = json!({"category": "tips", "title": "t", "summary": "s"});
    let bad = |k: &str, v: Value| {
        let mut body = ok.clone();
        body[k] = v;
        body
    };
    for body in [
        bad("category", json!("x")),
        bad("title", json!("a".repeat(61))),
        bad("title", json!("  ")),
        bad("summary", json!("a".repeat(121))),
        bad("send_at", json!("besok")),
    ] {
        let res = app.post_json(BC, Some(&b), &body).await;
        assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
        assert_eq!(res.json["error"]["code"], "invalid_value");
    }
    let res = app
        .post_json(BC, Some(&b), &bad("send_at", json!(in_minutes(-1))))
        .await;
    assert_eq!(res.json["error"]["code"], "time_passed");

    let res = app.post_json(BC, Some(&b), &bad("body", json!("  "))).await;
    assert_eq!(res.status, StatusCode::CREATED);
    assert_eq!(res.json["body"], Value::Null);
    assert_eq!(res.json["effective_status"], "sent");
    assert_eq!(res.json["created_by_name"], "Admin");
}

#[tokio::test]
async fn cancelled_is_hidden_from_lists_but_has_detail() {
    let app = TestApp::new().await;
    let b = broadcaster(&app, "a@example.com").await;
    let other = broadcaster(&app, "b@example.com").await;
    app.register("Siti", "siti@example.com", "password123")
        .await;
    make(&app, &b, "sent1", json!(null)).await;
    make(&app, &b, "sent2", json!(null)).await;
    make(&app, &b, "soon", json!(in_minutes(30))).await;
    let gone = make(&app, &b, "gone", json!(in_minutes(60))).await;

    // Another broadcaster may cancel it.
    let res = app
        .post_json(
            &format!("{BC}/{}/cancel", gone["id"]),
            Some(&other),
            &json!({}),
        )
        .await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    assert_eq!(res.json["effective_status"], "cancelled");

    let res = app.get(BC, Some(&b)).await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    assert_eq!(res.json["recipient_count"], 1);
    assert_eq!(titles(&res.json["scheduled"]), ["soon"]);
    assert_eq!(titles(&res.json["sent"]["items"]), ["sent2", "sent1"]);

    let res = app.get(&format!("{BC}/{}", gone["id"]), Some(&b)).await;
    assert_eq!(res.json["effective_status"], "cancelled");
    assert_eq!(res.json["cancelled_by_name"], "Admin");
    assert!(res.json["cancelled_at"].is_string());

    let res = app.get(&format!("{BC}?limit=1"), Some(&b)).await;
    assert_eq!(titles(&res.json["sent"]["items"]), ["sent2"]);
    let cursor = res.json["sent"]["next_cursor"].as_str().unwrap();
    let res = app
        .get(&format!("{BC}?limit=1&cursor={cursor}"), Some(&b))
        .await;
    assert_eq!(titles(&res.json["sent"]["items"]), ["sent1"]);
    assert_eq!(res.json["sent"]["next_cursor"], Value::Null);
}

#[tokio::test]
async fn permissions() {
    let app = TestApp::new().await;
    let b = broadcaster(&app, "a@example.com").await;
    let user = app
        .register("Siti", "siti@example.com", "password123")
        .await;
    let made = make(&app, &b, "x", json!(in_minutes(60))).await;
    let one = format!("{BC}/{}", made["id"]);
    let body = json!({"category": "info", "title": "t", "summary": "s"});

    for (res, what) in [
        (app.get(BC, Some(&user)).await, "list"),
        (app.post_json(BC, Some(&user), &body).await, "create"),
        (app.get(&one, Some(&user)).await, "detail"),
        (
            app.patch_json(&one, Some(&user), &json!({"title": "y"}))
                .await,
            "patch",
        ),
        (
            app.post_json(&format!("{one}/cancel"), Some(&user), &json!({}))
                .await,
            "cancel",
        ),
    ] {
        assert_eq!(res.status, StatusCode::FORBIDDEN, "{what}");
    }
    assert_eq!(app.get(FEED, None).await.status, StatusCode::UNAUTHORIZED);
    assert_eq!(app.get(BC, None).await.status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn promote_and_demote_bump_token_version() {
    let app = TestApp::new().await;
    let token = app
        .register("Siti", "siti@example.com", "password123")
        .await;
    let run = |cmd: &str, email: &str| {
        std::process::Command::new(env!("CARGO_BIN_EXE_backend"))
            .args([cmd, email])
            .env("DATABASE_URL", &app.config.database_url)
            .env("JWT_SECRET", common::TEST_JWT_SECRET)
            .env("APP_ENV", "development")
            .output()
            .unwrap()
    };

    assert!(run("promote", "siti@example.com").status.success());
    // The old JWT is rejected right away.
    assert_eq!(
        app.get(FEED, Some(&token)).await.status,
        StatusCode::UNAUTHORIZED
    );
    let row = app
        .client()
        .await
        .query_one("SELECT role_id, token_version FROM users", &[])
        .await
        .unwrap();
    assert_eq!((row.get::<_, i32>(0), row.get::<_, i32>(1)), (2, 1));

    assert!(run("demote", "siti@example.com").status.success());
    let row = app
        .client()
        .await
        .query_one("SELECT role_id, token_version FROM users", &[])
        .await
        .unwrap();
    assert_eq!((row.get::<_, i32>(0), row.get::<_, i32>(1)), (1, 2));

    assert_eq!(run("promote", "nobody@example.com").status.code(), Some(1));
}
