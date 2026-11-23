# Headless Android e2e image for Steiner Budget CI (e2e-android stage).
#
# Bake it ONCE on the runner VM; pull_policy = if-not-present means the runner
# picks the locally-built tag straight from the host image store — no registry:
#
#   git clone http://192.168.1.98/Steiner-Bot/local-budget-app.git lb-e2e
#   docker build -t localbudget-e2e:latest lb-e2e/docker/e2e-android
#   rm -rf lb-e2e
#
# Rebuild when Flutter floor or system image changes; CI comment tracks it.
FROM ghcr.io/cirruslabs/flutter:stable

# stdlib python3 for tools/ci/widget_dex_gate.py (Glance dex gate, launch
# blocker 2026-11-23). The wrapper can apt-install at runtime, but the
# release jobs should not bet the pipeline on package mirrors.
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends python3 \
 && rm -rf /var/lib/apt/lists/*

# Emulator + x86_64 Google-APIs system image (boots under the KVM device the
# runner passes into job containers) + platforms covering the 3.44 floor's
# compileSdk through current stable.
RUN set -eux; \
    yes | sdkmanager --licenses > /dev/null; \
    sdkmanager --install "emulator" "platforms;android-34" "platforms;android-35" \
      "platforms;android-36" "ndk;28.2.13676358" "cmake;3.22.1" \
      "system-images;android-36;google_apis;x86_64" > /dev/null; \
    echo no | avdmanager create avd -n ci \
      -k "system-images;android-36;google_apis;x86_64" -d pixel_7
