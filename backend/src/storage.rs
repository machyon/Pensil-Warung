//! Object storage for product photos: Tigris (S3) in production, an
//! in-memory fake in tests. The trait uses boxed futures so it can live
//! behind `Arc<dyn Storage>`.

use std::collections::HashMap;
use std::error::Error;
use std::future::Future;
use std::pin::Pin;
use std::sync::Mutex;
use std::time::Duration;

use aws_sdk_s3::Client;
use aws_sdk_s3::config::{BehaviorVersion, Credentials, Region, RequestChecksumCalculation};
use aws_sdk_s3::presigning::PresigningConfig;
use aws_sdk_s3::primitives::ByteStream;

use crate::config::StorageConfig;

pub type StorageError = Box<dyn Error + Send + Sync>;
type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = Result<T, StorageError>> + Send + 'a>>;

pub trait Storage: Send + Sync {
    fn put<'a>(&'a self, key: &'a str, bytes: Vec<u8>, content_type: &'a str) -> BoxFuture<'a, ()>;
    fn delete<'a>(&'a self, key: &'a str) -> BoxFuture<'a, ()>;
    /// A signed GET URL. Signing is local, so there is no network call.
    fn presign_get<'a>(&'a self, key: &'a str, ttl: Duration) -> BoxFuture<'a, String>;
}

pub struct TigrisStorage {
    client: Client,
    bucket: String,
}

impl TigrisStorage {
    /// Tigris wants region `auto` and the endpoint `https://t3.storage.dev`
    /// (`AWS_ENDPOINT_URL_S3`); the SDK's default virtual-host addressing works with it.
    pub fn new(config: &StorageConfig) -> Self {
        let credentials = Credentials::new(
            &config.access_key_id,
            &config.secret_access_key,
            None,
            None,
            "env",
        );
        let mut builder = aws_sdk_s3::Config::builder()
            .behavior_version(BehaviorVersion::latest())
            .region(Region::new(config.region.clone()))
            .credentials_provider(credentials)
            // S3-compatible stores may not accept the SDK's default checksum headers.
            .request_checksum_calculation(RequestChecksumCalculation::WhenRequired);
        if let Some(endpoint) = &config.endpoint_url {
            builder = builder.endpoint_url(endpoint);
        }
        Self {
            client: Client::from_conf(builder.build()),
            bucket: config.bucket.clone(),
        }
    }
}

impl Storage for TigrisStorage {
    fn put<'a>(&'a self, key: &'a str, bytes: Vec<u8>, content_type: &'a str) -> BoxFuture<'a, ()> {
        Box::pin(async move {
            self.client
                .put_object()
                .bucket(&self.bucket)
                .key(key)
                .content_type(content_type)
                .body(ByteStream::from(bytes))
                .send()
                .await?;
            Ok(())
        })
    }

    fn delete<'a>(&'a self, key: &'a str) -> BoxFuture<'a, ()> {
        Box::pin(async move {
            self.client
                .delete_object()
                .bucket(&self.bucket)
                .key(key)
                .send()
                .await?;
            Ok(())
        })
    }

    fn presign_get<'a>(&'a self, key: &'a str, ttl: Duration) -> BoxFuture<'a, String> {
        Box::pin(async move {
            let request = self
                .client
                .get_object()
                .bucket(&self.bucket)
                .key(key)
                .presigned(PresigningConfig::expires_in(ttl)?)
                .await?;
            Ok(request.uri().to_owned())
        })
    }
}

/// Test fake. A plain pub type because integration tests compile the lib
/// without `cfg(test)`.
#[derive(Default)]
pub struct MemoryStorage {
    /// key -> (bytes, content type)
    objects: Mutex<HashMap<String, (Vec<u8>, String)>>,
}

impl MemoryStorage {
    pub fn keys(&self) -> Vec<String> {
        let mut keys: Vec<String> = self.objects.lock().unwrap().keys().cloned().collect();
        keys.sort();
        keys
    }

    pub fn get(&self, key: &str) -> Option<(Vec<u8>, String)> {
        self.objects.lock().unwrap().get(key).cloned()
    }
}

impl Storage for MemoryStorage {
    fn put<'a>(&'a self, key: &'a str, bytes: Vec<u8>, content_type: &'a str) -> BoxFuture<'a, ()> {
        Box::pin(async move {
            let object = (bytes, content_type.to_owned());
            self.objects.lock().unwrap().insert(key.to_owned(), object);
            Ok(())
        })
    }

    fn delete<'a>(&'a self, key: &'a str) -> BoxFuture<'a, ()> {
        Box::pin(async move {
            self.objects.lock().unwrap().remove(key);
            Ok(())
        })
    }

    fn presign_get<'a>(&'a self, key: &'a str, ttl: Duration) -> BoxFuture<'a, String> {
        Box::pin(async move { Ok(format!("https://storage.test/{key}?ttl={}", ttl.as_secs())) })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn memory_storage_records_puts_and_deletes() {
        let s = MemoryStorage::default();
        s.put("a/b.jpg", vec![1, 2], "image/jpeg").await.unwrap();
        assert_eq!(s.keys(), ["a/b.jpg"]);
        assert_eq!(s.get("a/b.jpg").unwrap().1, "image/jpeg");
        assert_eq!(
            s.presign_get("a/b.jpg", Duration::from_secs(60))
                .await
                .unwrap(),
            "https://storage.test/a/b.jpg?ttl=60"
        );
        s.delete("a/b.jpg").await.unwrap();
        assert!(s.keys().is_empty());
    }
}
