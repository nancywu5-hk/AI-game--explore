import json
import os
import sys


def main():
    # Initialize default data structure
    data = {
        "version": "1.0.0",
        "build_status": {}
    }

    # Dictionary to map build folders to JSON keys
    build_map = {
        "web": "web",
        "android": "android",
        "windows": "windows",
        "linux": "linux",
        "macos": "macos",
        "ios": "ios"
    }

    # Iterate through expected builds and check for success markers
    for folder, key in build_map.items():
        # Check if the build folder exists
        build_dir = os.path.join("build", folder)

        status = "pending"

        if os.path.exists(build_dir):
            if os.path.exists(os.path.join(build_dir, "success")):
                 status = "success"
            elif os.path.exists(os.path.join(build_dir, "failure")):
                 status = "failed"
            else:
                 status = "unknown"
        else:
            status = "skipped"

        # Update JSON
        if "build_status" not in data:
            data["build_status"] = {}

        data["build_status"][key] = status
        print(f"Build {key}: {status}")

    # Output to public folder (for GitLab Pages)
    output_dir = "public"
    badges_dir = os.path.join(output_dir, "badges")
    os.makedirs(badges_dir, exist_ok=True)

    output_path = os.path.join(output_dir, "version.json")
    with open(output_path, 'w') as f:
        json.dump(data, f, indent=4)

    print(f"Updated version.json written to {output_path}")

    # Generate individual badge JSONs for Shields.io Endpoint
    # Schema: { "schemaVersion": 1, "label": "LABEL", "message": "MESSAGE", "color": "COLOR" }
    for key, status in data.get("build_status", {}).items():
        color = "inactive"
        if status == "success":
            color = "success" # Green
        elif status == "failed":
            color = "critical" # Red
        elif status == "pending":
            color = "yellow"

        badge_data = {
            "schemaVersion": 1,
            "label": key.capitalize(),
            "message": status,
            "color": color
        }

        badge_path = os.path.join(badges_dir, f"{key}.json")
        with open(badge_path, 'w') as f:
            json.dump(badge_data, f, indent=4)

        print(f"Generated badge for {key}: {badge_path}")


if __name__ == "__main__":
    main()
