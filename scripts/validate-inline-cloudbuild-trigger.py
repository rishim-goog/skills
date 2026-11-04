#!/usr/bin/env python3
"""Deterministic grader for Prompt #1 Scenario #5:
Remote repository missing Dockerfile / cloudbuild.yaml on origin/<DEFAULT_BRANCH>.

Checks:
1. Trigger created or updated using inline build config (not failing on missing remote cloudbuild.yaml)
2. Build config includes options.logging = CLOUD_LOGGING_ONLY (required when custom service account is used)
3. Build config includes options.requestedVerifyOption = VERIFIED (for SLSA provenance)
"""

import argparse
import json
import os
import subprocess


def run_cmd(cmd):
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return res.returncode == 0, res.stdout.strip(), res.stderr.strip()
    except Exception as exc:
        return False, "", str(exc)


def main():
    parser = argparse.ArgumentParser(
        description="Validate inline Cloud Build trigger config, CLOUD_LOGGING_ONLY, and VERIFIED provenance."
    )
    parser.add_argument("--workspace", default=".", help="Workspace directory")
    parser.add_argument(
        "--project-id", default=os.environ.get("PROJECT_ID", ""), help="GCP Project ID"
    )
    parser.add_argument(
        "--region", default=os.environ.get("REGION", "us-central1"), help="GCP Region"
    )
    args = parser.parse_args()

    inline_ok = False
    logging_ok = False
    provenance_ok = False

    if args.project_id:
        ok, out, _ = run_cmd(
            [
                "gcloud",
                "builds",
                "triggers",
                "list",
                f"--project={args.project_id}",
                f"--region={args.region}",
                "--format=json",
                "--quiet",
            ]
        )
        if ok and out and out != "[]":
            if '"build":' in out:
                inline_ok = True
            if "CLOUD_LOGGING_ONLY" in out:
                logging_ok = True
            if "VERIFIED" in out:
                provenance_ok = True

    for root, dirs, files in os.walk(args.workspace):
        dirs[:] = [d for d in dirs if d not in [".git", "node_modules", ".venv"]]
        for fname in files:
            if fname.endswith((".yaml", ".yml", ".json", ".sh")):
                fpath = os.path.join(root, fname)
                try:
                    with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
                        content = f.read()
                    if "inline-config" in content or "steps:" in content:
                        inline_ok = True
                    if "CLOUD_LOGGING_ONLY" in content:
                        logging_ok = True
                    if "VERIFIED" in content:
                        provenance_ok = True
                except Exception:
                    pass

    checks = [
        {"name": "inline-build-config-used", "passed": inline_ok},
        {"name": "cloud-logging-only-set", "passed": logging_ok},
        {"name": "slsa-provenance-verified-set", "passed": provenance_ok},
    ]
    passed = sum(1 for c in checks if c["passed"])
    score = round(passed / len(checks), 2)

    print(
        json.dumps(
            {
                "score": score,
                "details": f"{passed}/{len(checks)} inline Cloud Build trigger checks passed",
                "checks": checks,
            }
        )
    )


if __name__ == "__main__":
    main()
