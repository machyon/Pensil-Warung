//! Photo validation and resizing: any jpeg/png/webp in, a small JPEG out.

use std::io::Cursor;

use image::imageops::FilterType;
use image::{DynamicImage, ImageDecoder, ImageFormat, ImageReader, Limits, Rgb, RgbImage};

use crate::error::{AppError, AppResult, ErrorCode};

/// Longest side of a stored photo, in pixels.
const MAX_SIDE: u32 = 512;
const JPEG_QUALITY: u8 = 80;
/// Decompression-bomb guard on the decoded size.
const MAX_INPUT_SIDE: u32 = 8000;
const MAX_ALLOC_BYTES: u64 = 256 * 1024 * 1024;

pub const CONTENT_TYPE: &str = "image/jpeg";

fn unsupported() -> AppError {
    AppError::new(ErrorCode::UnsupportedImage)
}

/// Checks the magic bytes (the client's content type is ignored), decodes,
/// shrinks so the longest side is at most 512 px (never upscales), flattens
/// transparency onto white and returns JPEG bytes. CPU heavy: call it from
/// `spawn_blocking`. Anything that is not a decodable jpeg/png/webp is 415.
pub fn prepare(bytes: &[u8]) -> AppResult<Vec<u8>> {
    let format = image::guess_format(bytes).map_err(|_| unsupported())?;
    if !matches!(
        format,
        ImageFormat::Jpeg | ImageFormat::Png | ImageFormat::WebP
    ) {
        return Err(unsupported());
    }
    let mut limits = Limits::default();
    limits.max_image_width = Some(MAX_INPUT_SIDE);
    limits.max_image_height = Some(MAX_INPUT_SIDE);
    limits.max_alloc = Some(MAX_ALLOC_BYTES);
    let mut reader = ImageReader::with_format(Cursor::new(bytes), format);
    reader.limits(limits);
    let mut decoder = reader.into_decoder().map_err(|_| unsupported())?;
    // Phone photos carry their rotation in EXIF.
    let orientation = decoder.orientation().map_err(|_| unsupported())?;
    let mut img = DynamicImage::from_decoder(decoder).map_err(|_| unsupported())?;
    img.apply_orientation(orientation);
    if img.width().max(img.height()) > MAX_SIDE {
        img = img.resize(MAX_SIDE, MAX_SIDE, FilterType::Lanczos3);
    }
    let rgba = img.into_rgba8();
    let mut flat = RgbImage::new(rgba.width(), rgba.height());
    for (x, y, p) in rgba.enumerate_pixels() {
        let a = u32::from(p[3]);
        let over_white = |c: u8| ((u32::from(c) * a + 255 * (255 - a)) / 255) as u8;
        flat.put_pixel(
            x,
            y,
            Rgb([over_white(p[0]), over_white(p[1]), over_white(p[2])]),
        );
    }
    let mut out = Vec::new();
    flat.write_with_encoder(image::codecs::jpeg::JpegEncoder::new_with_quality(
        &mut out,
        JPEG_QUALITY,
    ))
    .map_err(|_| AppError::internal())?;
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{Rgba, RgbaImage};

    fn png(w: u32, h: u32, pixel: Rgba<u8>) -> Vec<u8> {
        let mut out = Vec::new();
        RgbaImage::from_pixel(w, h, pixel)
            .write_to(&mut Cursor::new(&mut out), ImageFormat::Png)
            .unwrap();
        out
    }

    fn decode(bytes: &[u8]) -> DynamicImage {
        assert_eq!(image::guess_format(bytes).unwrap(), ImageFormat::Jpeg);
        image::load_from_memory(bytes).unwrap()
    }

    #[test]
    fn transparent_png_becomes_white_jpeg() {
        let out = decode(&prepare(&png(40, 30, Rgba([255, 0, 0, 0]))).unwrap());
        assert_eq!((out.width(), out.height()), (40, 30));
        let p = out.to_rgb8().get_pixel(5, 5).0;
        assert!(p.iter().all(|c| *c > 245), "{p:?}");
    }

    #[test]
    fn wide_image_keeps_aspect_ratio() {
        let out = decode(&prepare(&png(1024, 256, Rgba([0, 0, 255, 255]))).unwrap());
        assert_eq!((out.width(), out.height()), (512, 128));
    }

    #[test]
    fn small_image_is_not_upscaled() {
        let out = decode(&prepare(&png(100, 50, Rgba([0, 0, 255, 255]))).unwrap());
        assert_eq!((out.width(), out.height()), (100, 50));
    }

    #[test]
    fn garbage_and_other_formats_are_rejected() {
        for bytes in [
            &b"not an image"[..],
            b"GIF89a\x01\x00\x01\x00",
            b"",
            b"\x89PNG\r\n\x1a\ntruncated",
        ] {
            let err = prepare(bytes).unwrap_err();
            assert_eq!(err.code(), ErrorCode::UnsupportedImage);
        }
    }

    #[test]
    fn oversized_dimensions_are_rejected() {
        let err = prepare(&png(8001, 1, Rgba([0, 0, 0, 255]))).unwrap_err();
        assert_eq!(err.code(), ErrorCode::UnsupportedImage);
    }
}
