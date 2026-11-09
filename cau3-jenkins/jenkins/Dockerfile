# Jenkins controller cho Lab 2 - Câu 3
#   - Cài sẵn plugin (plugins.txt) + cấu hình bằng code (JCasC: casc.yaml)
#   - Có docker CLI (dùng Docker daemon của host qua /var/run/docker.sock)
#   - Có kubectl để deploy lên k3s
FROM jenkins/jenkins:lts-jdk21

USER root

# Docker CLI + buildx (từ repo chính thức của Docker) và một số tiện ích
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg jq git \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
 && chmod a+r /etc/apt/keyrings/docker.asc \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin \
 && rm -rf /var/lib/apt/lists/*

# kubectl (phiên bản stable mới nhất, có kiểm tra checksum)
RUN KVER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)" \
 && ARCH="$(dpkg --print-architecture)" \
 && curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/${ARCH}/kubectl" \
 && echo "$(curl -fsSL "https://dl.k8s.io/release/${KVER}/bin/linux/${ARCH}/kubectl.sha256")  /usr/local/bin/kubectl" | sha256sum -c - \
 && chmod +x /usr/local/bin/kubectl

USER jenkins

# Bỏ wizard cài đặt, mọi cấu hình nằm trong casc.yaml
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
ENV CASC_JENKINS_CONFIG=/var/jenkins_casc/casc.yaml

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
