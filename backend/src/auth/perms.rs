//! Role permissions, loaded from `role_permission` once at startup.

use std::collections::{HashMap, HashSet};

use deadpool_postgres::Pool;

use super::extractor::AuthUser;
use crate::error::AppError;

/// One variant per seeded `permissions.name`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Perm {
    ProductManage,
    TransactionCreate,
    TransactionRead,
    TransactionVoid,
    AnalyticsRead,
    BroadcastRead,
    BroadcastCreate,
    BroadcastUpdate,
    BroadcastCancel,
}

impl Perm {
    pub fn from_name(name: &str) -> Option<Perm> {
        Some(match name {
            "product.manage" => Perm::ProductManage,
            "transaction.create" => Perm::TransactionCreate,
            "transaction.read" => Perm::TransactionRead,
            "transaction.void" => Perm::TransactionVoid,
            "analytics.read" => Perm::AnalyticsRead,
            "broadcast.read" => Perm::BroadcastRead,
            "broadcast.create" => Perm::BroadcastCreate,
            "broadcast.update" => Perm::BroadcastUpdate,
            "broadcast.cancel" => Perm::BroadcastCancel,
            _ => return None,
        })
    }

    /// The `permissions.name` value, also what the API returns in `permissions[]`.
    pub fn name(self) -> &'static str {
        match self {
            Perm::ProductManage => "product.manage",
            Perm::TransactionCreate => "transaction.create",
            Perm::TransactionRead => "transaction.read",
            Perm::TransactionVoid => "transaction.void",
            Perm::AnalyticsRead => "analytics.read",
            Perm::BroadcastRead => "broadcast.read",
            Perm::BroadcastCreate => "broadcast.create",
            Perm::BroadcastUpdate => "broadcast.update",
            Perm::BroadcastCancel => "broadcast.cancel",
        }
    }
}

/// role id -> permissions. Read-only after startup, so changing a role's
/// permissions in the database needs a restart.
#[derive(Debug, Default)]
pub struct Permissions(HashMap<i32, HashSet<Perm>>);

impl Permissions {
    pub async fn load(pool: &Pool) -> Result<Self, Box<dyn std::error::Error>> {
        let client = pool.get().await?;
        let rows = client
            .query(
                "SELECT rp.role_id, p.name FROM role_permission rp \
                 JOIN permissions p ON p.id = rp.permission_id",
                &[],
            )
            .await?;
        let mut map: HashMap<i32, HashSet<Perm>> = HashMap::new();
        for row in rows {
            let (role_id, name): (i32, String) = (row.get(0), row.get(1));
            match Perm::from_name(&name) {
                Some(perm) => {
                    map.entry(role_id).or_default().insert(perm);
                }
                None => {
                    tracing::warn!(permission = %name, "unknown permission in database, ignored")
                }
            }
        }
        Ok(Self(map))
    }

    pub fn has(&self, role_id: i32, perm: Perm) -> bool {
        self.0.get(&role_id).is_some_and(|set| set.contains(&perm))
    }

    /// 403 `forbidden` unless the user's role holds `perm`.
    pub fn require(&self, user: &AuthUser, perm: Perm) -> Result<(), AppError> {
        if self.has(user.role_id, perm) {
            Ok(())
        } else {
            Err(AppError::forbidden())
        }
    }

    /// Permission names of a role, sorted, for the `permissions[]` field of `user`.
    pub fn names(&self, role_id: i32) -> Vec<&'static str> {
        let mut names: Vec<_> = self
            .0
            .get(&role_id)
            .map(|set| set.iter().map(|p| p.name()).collect())
            .unwrap_or_default();
        names.sort_unstable();
        names
    }
}

#[cfg(test)]
mod tests {
    use uuid::Uuid;

    use super::*;
    use crate::error::ErrorCode;

    #[test]
    fn name_roundtrip() {
        for name in [
            "product.manage",
            "transaction.create",
            "transaction.read",
            "transaction.void",
            "analytics.read",
            "broadcast.read",
            "broadcast.create",
            "broadcast.update",
            "broadcast.cancel",
        ] {
            assert_eq!(Perm::from_name(name).unwrap().name(), name);
        }
        assert_eq!(Perm::from_name("nope"), None);
    }

    #[test]
    fn require_checks_the_role() {
        let perms = Permissions(HashMap::from([(
            1,
            HashSet::from([Perm::TransactionRead, Perm::ProductManage]),
        )]));
        let user = |role_id| AuthUser {
            id: Uuid::new_v4(),
            role_id,
        };
        assert!(perms.require(&user(1), Perm::TransactionRead).is_ok());
        let err = perms.require(&user(1), Perm::BroadcastCreate).unwrap_err();
        assert_eq!(err.code(), ErrorCode::Forbidden);
        assert!(perms.require(&user(99), Perm::TransactionRead).is_err());
        assert_eq!(perms.names(1), ["product.manage", "transaction.read"]);
        assert!(perms.names(99).is_empty());
    }
}
