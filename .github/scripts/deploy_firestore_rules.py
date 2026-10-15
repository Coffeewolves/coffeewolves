import json
import os
import sys
from pathlib import Path
from urllib.parse import urlencode
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def request_json(method, url, token, body=None):
    encoded_body = None if body is None else json.dumps(body).encode("utf-8")
    request = Request(
        url,
        data=encoded_body,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method=method,
    )
    try:
        with urlopen(request, timeout=30) as response:
            return json.load(response)
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"Firestore Rules API returned HTTP {error.code}: {detail}"
        ) from error
    except URLError as error:
        raise RuntimeError(f"Could not reach Firestore Rules API: {error}") from error


def main():
    project_id = os.environ.get("FIREBASE_PROJECT_ID", "").strip()
    access_token = os.environ.get("GOOGLE_OAUTH_ACCESS_TOKEN", "").strip()
    if not project_id or not access_token:
        raise RuntimeError("Firebase project ID and Google access token are required.")

    rules_path = Path("firestore.rules")
    if not rules_path.is_file():
        raise RuntimeError("firestore.rules was not found in the repository root.")

    api_base = "https://firebaserules.googleapis.com/v1"
    project_path = f"projects/{project_id}"
    ruleset = request_json(
        "POST",
        f"{api_base}/{project_path}/rulesets",
        access_token,
        {
            "source": {
                "files": [
                    {
                        "name": "firestore.rules",
                        "content": rules_path.read_text(encoding="utf-8"),
                    }
                ]
            }
        },
    )
    ruleset_name = ruleset.get("name")
    if not isinstance(ruleset_name, str) or not ruleset_name.startswith(
        f"{project_path}/rulesets/"
    ):
        raise RuntimeError("Firestore Rules API did not return a valid ruleset name.")

    release_name = f"{project_path}/releases/cloud.firestore"
    release = request_json(
        "PATCH",
        f"{api_base}/{release_name}?{urlencode({'updateMask': 'rulesetName'})}",
        access_token,
        {
            "name": release_name,
            "rulesetName": ruleset_name,
        },
    )
    if release.get("rulesetName") != ruleset_name:
        raise RuntimeError("Firestore release did not activate the uploaded ruleset.")

    print(f"Activated Firestore ruleset {ruleset_name}.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"::error::{error}", file=sys.stderr)
        raise
