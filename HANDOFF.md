# Ghi chú bàn giao – NT548 Lab 2

> Đọc file này trước khi làm tiếp. Hướng dẫn đầy đủ từng câu nằm trong [README.md](README.md).
> Khi hỏi trợ lý AI (Claude, ChatGPT…), **dán mục 9 "Bối cảnh cho trợ lý AI"** vào đầu cuộc chat, kèm theo file README/HANDOFF nếu chat cho phép đính kèm.
>
> **Không bao giờ** dán vào chat hoặc commit lên Git: AWS Secret Access Key, private key SSH, Docker Hub token, mật khẩu trong `.env`.

---

## 1. Tình trạng hiện tại (cập nhật 10/11/2026)

| Câu | Nội dung | Trạng thái |
|---|---|---|
| 1 | Terraform + GitHub Actions + Checkov | ✅ **Xong.** Pipeline chạy xanh (Checkov → fmt/validate → plan → duyệt → apply). Đã kiểm tra kết nối và **đã destroy** hạ tầng. Hạ tầng bootstrap (S3 state bucket, OIDC provider, IAM role) **vẫn còn**. |
| 2 | CloudFormation + CodeBuild (cfn-lint, taskcat) + CodePipeline | ✅ **Pipeline chạy xanh cả 4 stage.** Đã kiểm tra kết nối qua Session Manager. Xem chú ý bên dưới bảng. |
| 3 | Jenkins + SonarQube + Trivy + k3s trên EC2 | ⏳ **Đã viết code, CHƯA triển khai/chạy thử lần nào.** Đây là phần làm tiếp. |

Chú ý cho Câu 2 (trên account của người làm trước):
- Stack hạ tầng `nt548-lab2-cfn-infra` **đã xóa** (10/11) để không tốn phí. Stack pipeline `nt548-lab2-pipeline`, repo CodeCommit và bootstrap Câu 1 vẫn còn. Muốn dựng lại hạ tầng: CodePipeline → **Release change** → Approve.
- Commit `8a7659b` (sửa PassRole) mới push lên GitHub, **chưa push lên CodeCommit**. Stack pipeline trên AWS đã được cập nhật tay bằng `aws cloudformation deploy` nên vẫn chạy đúng. Muốn đồng bộ thì `git push codecommit main`; lệnh này sẽ kích hoạt pipeline chạy lại và cần bấm Approve.

**Làm lại trên AWS account riêng của bạn?** → làm theo **mục 5** từ trên xuống, có đủ Câu 1 và Câu 2.

---

## 2. Tài khoản & quyền cần có

1. **AWS**
   - Nếu dùng chung account: chủ account tạo cho bạn **IAM user riêng** (lab: `AdministratorAccess`), rồi bạn tự tạo Access Key. **Không** xin key của người khác.
   - Nếu dùng account riêng: làm theo mục 5. **Đọc kỹ mục 5.0 về kiểu đăng ký account và region.**
   - Region dùng cho toàn bộ lab: **`ap-southeast-1` (Singapore)**.
   - Nên tạo **AWS Budget** (Zero-spend hoặc khoảng 5–10 USD) để có email cảnh báo phí.
2. **GitHub**
   - Được thêm làm collaborator của repo (quyền Write/Admin) để chạy Actions và sửa Variables/Environments, **hoặc** fork/transfer repo. Nếu repo đổi chủ hoặc đổi tên thì phải sửa OIDC (mục 5.1).
3. **Docker Hub** (cho Câu 3): tài khoản + Personal Access Token quyền Read & Write.

---

## 3. Công cụ trên máy (Windows 10/11, dùng terminal PowerShell trong VS Code)

```powershell
winget install -e --id Amazon.AWSCLI
winget install -e --id Hashicorp.Terraform          # cần >= 1.17 (CI dùng ~1.17.0)
winget install -e --id Amazon.SessionManagerPlugin  # SSH/port-forward qua SSM, không cần mở port 22
winget install -e --id Git.Git
```

Sau khi cài, **nạp lại PATH** (hoặc mở terminal mới):

```powershell
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
aws --version; terraform version; session-manager-plugin
```

Cấu hình AWS CLI:

```powershell
aws configure            # Access Key của CHÍNH BẠN, region ap-southeast-1, output json
aws sts get-caller-identity
```

Tạo SSH key nếu chưa có. Chỉ chia sẻ file `.pub`.

```powershell
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\nt548-lab2" -C "nt548-lab2"
```

---

## 4. Những thứ đã cấu hình sẵn (giá trị hiện tại)

### 4.1 GitHub repo `than8505/NT548-Lab2`

**Settings → Secrets and variables → Actions → Variables** (không dùng Secrets):

| Variable | Ý nghĩa | Lấy từ đâu |
|---|---|---|
| `AWS_REGION` | `ap-southeast-1` | |
| `AWS_ROLE_ARN` | IAM role cho GitHub OIDC | `terraform output github_actions_role_arn` trong `cau1-terraform/bootstrap` |
| `TF_STATE_BUCKET` | S3 bucket chứa Terraform state | `terraform output state_bucket` |
| `ALLOWED_SSH_CIDR` | IP được SSH vào bastion (`x.x.x.x/32`) | Hiện đặt cố định 1 IP; vì truy cập qua SSM nên **không cần đổi** khi IP thay đổi |
| `SSH_PUBLIC_KEY` | nội dung `nt548-lab2.pub` | |

**Settings → Environments → `production`**: bật *Required reviewers*. Job apply/destroy chỉ chạy sau khi người được chỉ định bấm Approve. Nhớ **thêm bạn vào danh sách reviewer**.

### 4.2 AWS (account hiện tại)

| Thành phần | Tên |
|---|---|
| Bootstrap Câu 1 | S3 bucket state (prefix `nt548-lab2-tfstate-…`), GitHub OIDC provider, IAM role cho Actions. File state bootstrap **chỉ nằm trên máy người làm trước** (không có trên Git) |
| Câu 2 – stack pipeline | `nt548-lab2-pipeline` (CodeCommit `nt548-lab2`, S3 artifact, 2 CodeBuild project, CodePipeline V2, EventBridge rule) |
| Câu 2 – stack hạ tầng | `nt548-lab2-cfn-infra` + 3 nested stack (do pipeline tạo) |
| Key pair EC2 | `nt548-lab2-cfn` (import từ `nt548-lab2.pub`) |

### 4.3 File tham số cần sửa nếu đổi người/IP/account

| File | Trường |
|---|---|
| `cau2-cloudformation/config/prod.json` | `AllowedSSHCidr`, `KeyName` |
| `cau3-jenkins/infra/terraform.tfvars` (copy từ `.example`) | `admin_cidr`, `lab_repo_url`, `ssh_public_key` |
| `cau3-jenkins/jenkins/.env` (trên máy Jenkins) | `DOCKERHUB_USER`, `DOCKERHUB_TOKEN`, `JENKINS_ADMIN_PASSWORD`, `SONAR_ADMIN_PASSWORD`, `POSTGRES_PASSWORD` |

---

## 5. Nếu dùng AWS account khác / repo khác

### 5.1 Câu 1 – Bootstrap lại

GitHub hiện gửi OIDC claim `sub` dạng **immutable ID**, ví dụ `repo:than8505@181867933/NT548-Lab2@1451096886:pull_request`. Vì vậy bootstrap cần thêm ID số của owner và repo:

```powershell
# Lấy ID (thay owner/repo):
Invoke-RestMethod https://api.github.com/repos/<owner>/<repo> | Select-Object @{n='repo_id';e={$_.id}}, @{n='owner_id';e={$_.owner.id}}

cd cau1-terraform/bootstrap
terraform init
terraform apply -var="github_repo=<owner>/<repo>" -var="aws_region=ap-southeast-1" `
                -var="github_owner_id=<owner_id>" -var="github_repo_id=<repo_id>"
# Account đã có GitHub OIDC provider → thêm: -var="create_github_oidc_provider=false"
terraform output
```

Sau đó cập nhật lại các GitHub Variables ở mục 4.1.

### 5.2 Câu 2 – Tạo pipeline

```powershell
aws cloudformation deploy --stack-name nt548-lab2-pipeline `
  --template-file cau2-cloudformation/pipeline/pipeline.yaml `
  --capabilities CAPABILITY_IAM --region ap-southeast-1 `
  --parameter-overrides RepositoryName=nt548-lab2 BranchName=main EnableTaskcat=true EnableManualApproval=true
```

Đẩy code lên CodeCommit qua HTTPS, dùng credential helper của AWS CLI:

```powershell
git remote add codecommit https://git-codecommit.ap-southeast-1.amazonaws.com/v1/repos/nt548-lab2
# PowerShell 5.1 làm rơi chuỗi rỗng "" => phải chạy qua cmd /c để tắt Git Credential Manager cho host này
cmd /c 'git config --local credential.https://git-codecommit.ap-southeast-1.amazonaws.com.helper ""'
git config --local --add credential.https://git-codecommit.ap-southeast-1.amazonaws.com.helper '!aws codecommit credential-helper $@'
git config --local credential.https://git-codecommit.ap-southeast-1.amazonaws.com.UseHttpPath true
git push codecommit main
```

---

## 6. Truy cập EC2 bằng Session Manager (không phụ thuộc IP)

Mọi EC2 trong lab đều có IAM role `AmazonSSMManagedInstanceCore`. Thêm vào `~/.ssh/config` (thay `<INSTANCE_ID>` bằng ID thật, `<PRIVATE_IP>` bằng IP private):

```
Host cfn-bastion
    HostName <INSTANCE_ID_PUBLIC_EC2>
    User ec2-user
    IdentityFile ~/.ssh/nt548-lab2
    ProxyCommand aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p --region ap-southeast-1

Host cfn-private
    HostName <PRIVATE_IP_PRIVATE_EC2>
    User ec2-user
    IdentityFile ~/.ssh/nt548-lab2
    ProxyJump cfn-bastion
```

Lấy ID/IP: `aws ec2 describe-instances --region ap-southeast-1 --filters Name=instance-state-name,Values=running --query "Reservations[].Instances[].[InstanceId,PrivateIpAddress,PublicIpAddress,Tags[?Key=='Name']|[0].Value]" --output table`

Kiểm tra (kết quả đã đạt ở Câu 1 và Câu 2):

```powershell
ssh cfn-bastion "hostname -I; curl -s https://checkip.amazonaws.com"   # ra Public IP của bastion (đi qua IGW)
ssh cfn-private "hostname -I; curl -s https://checkip.amazonaws.com"   # ra IP của NAT Gateway
```

**Câu 3 (dự kiến):** máy Jenkins và k3s dùng Ubuntu (user `ubuntu`). Để xem UI mà không phải mở port theo IP, dùng port-forward qua SSM:

```powershell
aws ssm start-session --target <JENKINS_INSTANCE_ID> --region ap-southeast-1 `
  --document-name AWS-StartPortForwardingSession --parameters "portNumber=8080,localPortNumber=8080"
# mở http://localhost:8080 ; SonarQube: đổi 8080 -> 9000 rồi mở http://localhost:9000
```

---

## 7. Chi phí & dọn dẹp

Tài nguyên tốn tiền theo giờ: **NAT Gateway** (đắt nhất), **EC2**, Elastic IP, và EC2 của Câu 3 (Jenkins + SonarQube cần máy lớn). Làm xong phiên nào thì xóa hạ tầng của phiên đó.

Kiểm tra nhanh còn gì đang chạy:

```powershell
aws ec2 describe-instances --region ap-southeast-1 --filters Name=instance-state-name,Values=running,pending --query "Reservations[].Instances[].InstanceId" --output text
aws ec2 describe-nat-gateways --region ap-southeast-1 --filter Name=state,Values=available,pending --query "NatGateways[].NatGatewayId" --output text
aws ec2 describe-addresses --region ap-southeast-1 --query "Addresses[].PublicIp" --output text
aws cloudformation list-stacks --region ap-southeast-1 --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE ROLLBACK_COMPLETE --query "StackSummaries[].StackName" --output text
aws s3 ls
```

Xóa:
- **Câu 1:** GitHub → Actions → *Cau 1 - Terraform CI/CD* → Run workflow → `destroy` → Approve.
- **Câu 2:** `aws cloudformation delete-stack --stack-name nt548-lab2-cfn-infra --region ap-southeast-1`. Sau đó xóa bucket `tcat-…` còn sót (nếu có). Stack pipeline gần như không tốn phí khi không chạy; muốn xóa hẳn xem README mục 4.
- **Câu 3:** `cd cau3-jenkins/infra; terraform destroy`.

---

## 8. Các lỗi đã gặp & cách đã sửa (để không mất thời gian lần nữa)

| Lỗi | Nguyên nhân → Cách sửa |
|---|---|
| `aws` / `terraform` / `session-manager-plugin` "not recognized" | PATH chưa nạp trong terminal VS Code → chạy lệnh nạp PATH ở mục 3 |
| `SignatureDoesNotMatch` / lỗi thời gian khi gọi AWS | Đồng hồ Windows lệch → Settings → Time → bật *Set time automatically* + *Sync now*, đúng múi giờ UTC+7 |
| GitHub push bị chặn "secret detected" | Có Stripe key cứng trong test → đã chuyển sang biến môi trường `STRIPE_TEST_KEY`, test Stripe thật bị `skip` nếu không có key |
| Checkov fail `CKV_AWS_394`, `CKV_AWS_24`, `CKV2_AWS_5` | Ghim AZ cứng trong `main.tf`; 2 check còn lại là false positive → `#checkov:skip` kèm lý do |
| Actions: `Not authorized to perform sts:AssumeRoleWithWebIdentity` | GitHub dùng `sub` dạng immutable ID → bootstrap với `github_owner_id`, `github_repo_id` (mục 5.1). Xem chi tiết lỗi trong CloudTrail, event `AssumeRoleWithWebIdentity` |
| SSH timeout vào bastion | IP máy đổi khi di chuyển → dùng Session Manager (mục 6), không SSH trực tiếp |
| GitHub Environment "problem approving one of the gates" | Tải lại trang, bấm Approve **một lần** |
| Git Credential Manager bật popup khi push CodeCommit | Cấu hình helper như mục 5.2 (`cmd /c` cho chuỗi rỗng) |
| `aws ... \| Out-File` hoặc `aws cloudformation deploy` lỗi `charmap codec` | AWS CLI trên Windows dùng cp1252 → in thẳng ra terminal; **giữ các file AWS CLI đọc từ máy (`pipeline.yaml`, template) chỉ chứa ký tự ASCII** (không viết comment tiếng Việt có dấu) |
| cfn-lint report JUnit lỗi | Cài `cfn-lint[junit]` (đã sửa trong `buildspecs/lint-package.yml`) |
| taskcat `No module named pkg_resources` | Ghim `setuptools<81` (đã sửa trong `buildspecs/taskcat.yml`) |
| taskcat S3 "must be addressed using the specified endpoint" | `s3_regional_buckets: true` trong `.taskcat.yml` |
| Deploy stage: role CloudFormation không được `iam:PassRole` | Nested stack cần role tự PassRole chính nó → resource `CloudFormationDeployRolePassSelf` trong `pipeline.yaml` |
| Stack ở `ROLLBACK_COMPLETE` | Phải xóa stack rồi *Retry* action Deploy trong CodePipeline |
| File `.sh` không chạy được trên Linux | Commit từ Windows mất quyền thực thi → `git add --chmod=+x <file>.sh`; repo dùng `.gitattributes` `eol=lf` |
| SSM báo `ValidationException ... target` | Còn placeholder trong `~/.ssh/config` → thay bằng instance ID thật |

---

## 9. Bối cảnh cho trợ lý AI (copy nguyên khối này vào đầu cuộc chat)

```text
Tôi đang làm tiếp bài NT548 Lab 2 (DevOps) trong repo GitHub than8505/NT548-Lab2 (người khác làm trước, tôi nhận bàn giao).
Máy tôi: Windows, terminal PowerShell trong VS Code. AWS region ap-southeast-1.

Cấu trúc repo:
- cau1-terraform/: Terraform (AWS provider ~>6.0, Terraform ~1.17) dựng VPC, public/private subnet, IGW, NAT GW, route tables,
  2 EC2 (bastion public + private), Security Groups; modules vpc/security-groups/ec2; S3 backend dùng use_lockfile.
  cau1-terraform/bootstrap/ tạo S3 state bucket + GitHub OIDC provider + IAM role (state bootstrap để local).
  CI: .github/workflows/terraform.yml + composite action .github/actions/terraform-setup:
  Checkov (SARIF) -> fmt/validate -> plan (comment PR, artifact tfplan) -> apply/destroy qua environment "production" có required reviewer.
  Biến lấy từ GitHub Variables: AWS_REGION, AWS_ROLE_ARN, TF_STATE_BUCKET, ALLOWED_SSH_CIDR, SSH_PUBLIC_KEY.
  OIDC trust chấp nhận cả sub "repo:owner/repo:*" và dạng immutable "repo:owner@OWNERID/repo@REPOID:*".
- cau2-cloudformation/: nested stacks templates/main.yaml -> vpc.yaml, security-groups.yaml, ec2.yaml; tham số config/prod.json.
  pipeline/pipeline.yaml (stack "nt548-lab2-pipeline"): CodeCommit nt548-lab2 -> CodePipeline V2:
  Source -> Validate (CodeBuild buildspecs/lint-package.yml: cfn-lint + validate-template + upload templates S3 releases/<commit>/;
  CodeBuild buildspecs/taskcat.yml: taskcat test) -> Approve (manual) -> Deploy CloudFormation CREATE_UPDATE stack "nt548-lab2-cfn-infra".
  pipeline.yaml phải giữ ASCII-only vì AWS CLI Windows đọc cp1252.
- cau3-jenkins/: ứng dụng microservices Aurapan (tuan-devops/microservices-ecommerce) trong app/;
  infra/ Terraform tạo EC2 Jenkins + EC2 k3s (Ubuntu, có role SSM, S3 bucket chuyển kubeconfig);
  jenkins/ Dockerfile + plugins.txt + casc.yaml (JCasC) + docker-compose.yml (Jenkins + SonarQube + Postgres) + bootstrap.sh + .env.example;
  Jenkinsfile: detect-changes -> unit test -> SonarQube + Quality Gate -> Trivy fs/image (aquasec/trivy:0.58.1) -> build/push Docker Hub
  -> deploy k3s bằng kustomize (scripts/deploy.sh) với ServiceAccount jenkins-deployer -> smoke-test.

Tình trạng: Câu 1 và Câu 2 đã chạy xanh và kiểm tra xong. Câu 3 đã viết code nhưng CHƯA chạy thử lần nào.
Quy ước truy cập EC2: dùng SSM Session Manager (ssh ProxyCommand AWS-StartSSHSession, port-forward AWS-StartPortForwardingSession),
không mở port theo IP vì IP của tôi hay đổi.

Cách hướng dẫn tôi: từng bước một, mỗi bước một lệnh (lệnh nào bắt buộc chạy cùng lúc thì đưa cùng).
Tôi gửi kết quả/ảnh rồi mới qua bước kế; tôi nhắn "Tiếp tục" để sang bước sau.
Không yêu cầu tôi gửi AWS secret key, private key hay token. Nhắc tôi xóa tài nguyên tốn phí (NAT, EC2) khi tạm dừng.
```

---

## 10. Việc cần làm tiếp

- [ ] (Câu 2) Chụp minh chứng nếu còn thiếu: CodeCommit, CodePipeline 4 stage xanh, CodeBuild log + Report group, CloudFormation stack/outputs, VPC/route tables/NAT, EC2/SG.
- [ ] (Câu 2) `git push codecommit main` để đồng bộ commit sửa PassRole, rồi xóa `nt548-lab2-cfn-infra` khi chụp xong.
- [ ] (Câu 3) Push repo lên GitHub ở chế độ **public** (máy Jenkins clone repo lúc khởi động) → `cau3-jenkins/infra` `terraform apply` → điền `.env` → `./bootstrap.sh` → chạy job `aurapan-microservices` với `BUILD_ALL` → chụp Jenkins Stage View, SonarQube, báo cáo Trivy, Docker Hub, `kubectl get pods`, trang web.
- [ ] Dọn dẹp toàn bộ (mục 7). Cuối cùng xóa bootstrap Câu 1 (`terraform destroy -var="force_destroy_state_bucket=true" ...` trên máy có state bootstrap).
