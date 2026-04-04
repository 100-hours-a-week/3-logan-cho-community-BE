import json
import os
import time
import urllib.error
import urllib.request
from io import BytesIO

import boto3
from PIL import Image, ImageOps


CONTENT_MAX_SIZE = 1600
CONTENT_QUALITY = 82
THUMBNAIL_MAX_SIZE = 320
THUMBNAIL_QUALITY = 60
CALLBACK_SECRET = os.environ["IMAGE_PIPELINE_CALLBACK_SECRET"]

s3 = boto3.client("s3")


def _convert(image_bytes, max_size, quality):
    image = Image.open(BytesIO(image_bytes))
    image = ImageOps.exif_transpose(image).convert("RGB")
    image.thumbnail((max_size, max_size))
    output = BytesIO()
    image.save(output, format="JPEG", quality=quality, optimize=True)
    return output.getvalue()


def _uuid_key(prefix, image_job_id, index):
    return f"{prefix}/{image_job_id}-{index}.jpg"


def _load_bytes(bucket, key):
    return s3.get_object(Bucket=bucket, Key=key)["Body"].read()


def _put_bytes(bucket, key, body):
    s3.put_object(Bucket=bucket, Key=key, Body=body, ContentType="image/jpeg")


def _callback(url, payload):
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "X-Experiment-Callback-Secret": CALLBACK_SECRET,
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        if response.status >= 300:
            raise RuntimeError(f"callback failed with status={response.status}")


def _process_message(message):
    body = json.loads(message["body"])
    bucket = body["bucket"]
    image_job_id = body["imageJobId"]
    post_id = body["postId"]
    temp_keys = body["tempImageKeys"]
    callback_url = body["callbackUrl"]

    started_at = time.time()
    final_keys = []
    thumbnail_keys = []

    for index, temp_key in enumerate(temp_keys):
        original = _load_bytes(bucket, temp_key)
        final_key = _uuid_key("public/images/posts", image_job_id, index)
        thumbnail_key = _uuid_key("public/images/posts/thumbnails", image_job_id, index)

        _put_bytes(bucket, final_key, _convert(original, CONTENT_MAX_SIZE, CONTENT_QUALITY))
        _put_bytes(bucket, thumbnail_key, _convert(original, THUMBNAIL_MAX_SIZE, THUMBNAIL_QUALITY))

        final_keys.append(final_key)
        thumbnail_keys.append(thumbnail_key)

    _callback(
        callback_url,
        {
            "imageJobId": image_job_id,
            "imageStatus": "COMPLETED",
            "finalImageKeys": final_keys,
            "thumbnailKeys": thumbnail_keys,
            "failureReason": None,
        },
    )

    return {
        "postId": post_id,
        "imageJobId": image_job_id,
        "processedCount": len(temp_keys),
        "durationMs": int((time.time() - started_at) * 1000),
    }


def handler(event, context):
    results = []
    for record in event.get("Records", []):
        try:
            results.append(_process_message(record))
        except Exception as exc:
            body = json.loads(record["body"])
            try:
                _callback(
                    body["callbackUrl"],
                    {
                        "imageJobId": body["imageJobId"],
                        "imageStatus": "FAILED",
                        "finalImageKeys": [],
                        "thumbnailKeys": [],
                        "failureReason": str(exc)[:300],
                    },
                )
            except urllib.error.URLError:
                pass
            raise
    return {"processed": results}
