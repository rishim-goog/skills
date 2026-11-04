#!/usr/bin/env python3
"""Deterministic grader for Prompt #2 & Subprompt 2.1:
Generate deployment-config.json based on enabled/specified GCP services and deploy sample app.

Scoring Criteria from evaluation spec:
1. Success of deploying a sample application MUST be the most important success criterion (weight: 0.55).
2. Using the defined/enabled services MUST be part of the scoring criteria (weight: 0.25).
3. Proper generation of deployment-config.json schema without unpopulated placeholders (weight: 0.20).
"""

import argparse
import json
import os
import subprocess
import urllib.request


def run_cmd(cmd):
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return res.returncode == 0, res.stdout.strip(), res.stderr.strip()
    except Exception as exc:
        return False, "", str(exc)


def find_config_file(workspace_dir):
    candidates = [
        os.path.join(workspace_dir, ".gcp-deploy", "deployment-config.json"),
        os.path.join(workspace_dir, "deployment-config.json"),
        os.path.join(workspace_dir, "gcp-deploy.json"),
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    return None


def validate_schema(cfg):
    """Checks that deployment-config.json conforms to the schema and has no placeholders."""
    raw = json.dumps(cfg)
    if "<PROJECT_ID>" in raw or "<REGION>" in raw or "TODO" in raw:
        return False, "Configuration contains unresolved placeholder tokens"

    has_common = isinstance(cfg.get("common_gcp_settings"), dict) and bool(
        cfg["common_gcp_settings"].get("project_id")
    )
    has_runtime = cfg.get("active_runtime") in ("Cloud Run", "GKE", "prompt")
    has_target_block = isinstance(cfg.get("cloud_run"), dict) or isinstance(
        cfg.get("gke"), dict
    )

    if has_common and has_runtime and has_target_block:
        return True, "deployment-config.json schema is valid and populated"
    return (
        False,
        f"Missing required schema keys (common_gcp_settings={has_common}, active_runtime={has_runtime}, target_block={has_target_block})",
    )


def validate_defined_services(cfg, required_services):
    """Verifies that each specified service (e.g., cloud_run, gke, artifact_registry, cloud_build, developer_connect) is configured."""
    if not required_services:
        return True, "No specific service filter provided"

    raw = json.dumps(cfg).lower()
    missing = []
    for svc in required_services:
        svc_norm = svc.strip().lower().replace("-", "_").replace(" ", "_")
        if svc_norm in ("cloud_run", "run"):
            if "cloud_run" not in cfg and cfg.get("active_runtime") != "Cloud Run":
                missing.append("Cloud Run")
        elif svc_norm in ("gke", "kubernetes"):
            if "gke" not in cfg and cfg.get("active_runtime") != "GKE":
                missing.append("GKE")
        elif svc_norm in ("artifact_registry", "ar"):
            if "artifact_registry" not in raw and "pkg.dev" not in raw:
                missing.append("Artifact Registry")
        elif svc_norm in ("cloud_build", "cloudbuild"):
            if (
                "cloud_build" not in raw
                and "developer_connect_and_cloud_build" not in cfg
            ):
                missing.append("Cloud Build")
        elif svc_norm in ("developer_connect", "devconnect", "dev_connect"):
            if (
                "developer_connect" not in raw
                and "connection_id" not in raw
            ):
                missing.append("Developer Connect")

    if not missing:
        return True, f"All defined services configured: {', '.join(required_services)}"
    return False, f"Missing configuration for defined services: {', '.join(missing)}"


def validate_sample_deployment(project_id, region, service_name, runtime):
    """Verifies that the sample application deployment succeeded (highest weight: 0.55)."""
    if runtime.lower() in ("cloud_run", "run", "cloud run"):
        if not project_id or not region or not service_name:
            return False, "Missing project_id, region, or service_name for Cloud Run verification"
        ok, url, err = run_cmd(
            [
                "gcloud",
                "run",
                "services",
                "describe",
                service_name,
                f"--project={project_id}",
                f"--region={region}",
                "--format=value(status.url)",
                "--quiet",
            ]
        )
        if not ok or not url:
            return False, f"Cloud Run service '{service_name}' not found: {err}"
        try:
            req = urllib.request.Request(url, method="GET")
            with urllib.request.urlopen(req, timeout=15) as resp:
                status = resp.getcode()
                if 200 <= status < 500:
                    return True, f"Sample app deployed and reachable at {url} (HTTP {status})"
        except urllib.error.HTTPError as e:
            if e.code < 500:
                return True, f"Sample app deployed and reachable at {url} (HTTP {e.code})"
            return False, f"Sample app returned HTTP {e.code} at {url}"
        except Exception as exc:
            return False, f"Could not reach deployed Cloud Run URL {url}: {exc}"

    elif runtime.lower() == "gke":
        ok, out, err = run_cmd(
            ["kubectl", "get", "deployments", "-A", "-o", "json"]
        )
        if ok and service_name in out:
            return True, f"Sample app GKE deployment '{service_name}' found in cluster"
        return False, f"GKE deployment '{service_name}' not found: {err}"

    return False, f"Unsupported runtime '{runtime}'"


def main():
    parser = argparse.ArgumentParser(
        description="Validate generated deployment-config.json and sample application deployment."
    )
    parser.add_argument("--workspace", default=".", help="Workspace directory")
    parser.add_argument(
        "--project-id", default=os.environ.get("PROJECT_ID", ""), help="GCP Project ID"
    )
    parser.add_argument(
        "--region", default=os.environ.get("REGION", "us-central1"), help="GCP Region"
    )
    parser.add_argument(
        "--service-name",
        default=os.environ.get("CLOUD_RUN_SERVICE", ""),
        help="Expected deployed sample service/workload name",
    )
    parser.add_argument(
        "--runtime",
        default="cloud_run",
        choices=["cloud_run", "gke"],
        help="Target runtime for sample deployment check",
    )
    parser.add_argument(
        "--required-services",
        default="cloud_run,artifact_registry,cloud_build,developer_connect",
        help="Comma-separated list of services that must be present in the generated config",
    )
    args = parser.parse_args()

    cfg_path = find_config_file(args.workspace)
    schema_ok = False
    schema_msg = "deployment-config.json not found in workspace"
    services_ok = False
    services_msg = "Skipped: deployment-config.json not found"

    if cfg_path:
        try:
            with open(cfg_path, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            schema_ok, schema_msg = validate_schema(cfg)
            req_list = [s for s in args.required_services.split(",") if s.strip()]
            services_ok, services_msg = validate_defined_services(cfg, req_list)
        except Exception as exc:
            schema_msg = f"Failed to parse {cfg_path}: {exc}"

    deploy_ok, deploy_msg = validate_sample_deployment(
        args.project_id, args.region, args.service_name, args.runtime
    )

    # Weights per evaluation spec:
    # - Sample app deployment success = 0.55 (most important criterion)
    # - Defined services used in config = 0.25
    # - Config file schema validity = 0.20
    score = 0.0
    if deploy_ok:
        score += 0.55
    if services_ok:
        score += 0.25
    if schema_ok:
        score += 0.20
    score = round(score, 2)

    print(
        json.dumps(
            {
                "score": score,
                "details": (
                    f"Prompt #2 score: {score:.2f} "
                    f"(deploy={deploy_ok} [0.55], services={services_ok} [0.25], config_schema={schema_ok} [0.20])"
                ),
                "checks": [
                    {
                        "name": "sample-app-deployment-succeeded",
                        "weight": 0.55,
                        "passed": deploy_ok,
                        "message": deploy_msg,
                    },
                    {
                        "name": "defined-services-configured",
                        "weight": 0.25,
                        "passed": services_ok,
                        "message": services_msg,
                    },
                    {
                        "name": "deployment-config-schema-valid",
                        "weight": 0.20,
                        "passed": schema_ok,
                        "message": schema_msg,
                    },
                ],
            }
        )
    )


if __name__ == "__main__":
    main()
