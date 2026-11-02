# Headless Android e2e image for LocalBudget CI (e2e-android stage).
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

# Emulator + x86_64 Google-APIs system image (boots under the KVM device the
# runner passes into job containers) + platforms covering the 3.44 floor's
# compileSdk through current stable.
RUN set -eux; \
    yes | sdkmanager --licenses > /dev/null; \
    sdkmanager --install "emulator" "platforms;android-35" "platforms;android-36" \
      "platforms;android-37" \
      "system-images;android-36;google_apis;x86_64" > /dev/null; \
    echo no | avdmanager create avd -n ci \
      -k "system-images;android-36;google_apis;x86_64" -d pixel_7
