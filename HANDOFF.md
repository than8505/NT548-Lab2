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
   - Được thêm làm collaborator của repo (quyền Write/Admin) để chạy Actions và sửa Variables/Environments, **hoặc** fork/transfer repo. Nếu repo đổi chủ hoặc đổi tên thì phải sửa OIDC (mục 5.2, 5.3).
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

## 5. Làm lại từ đầu trên AWS account khác (Câu 1 + Câu 2)

Làm lần lượt từ 5.0 đến 5.4. Mỗi lệnh dưới đây chạy trong PowerShell, tại **thư mục gốc repo** (trừ khi có `cd`).

### 5.0 Account AWS: kiểu đăng ký và region (QUAN TRỌNG)

Toàn bộ lab cố định region **`ap-southeast-1` (Singapore)**: workflow, `.taskcat.yml`, `pipeline.yaml`, các lệnh.

- AWS hiện có 2 kiểu đăng ký: **Sign up for AWS (new)** và **Sign up for AWS (advanced)**.
- Với kiểu **(new)**, AWS **tự gán region theo quốc gia trong địa chỉ liên hệ và không cho đổi**. Địa chỉ Việt Nam được gán **Sydney (`ap-southeast-2`)**, nên lab sẽ không chạy đúng.
- → Khi tạo account, chọn **Sign up for AWS (advanced)**. Nếu lỡ tạo kiểu (new) thì vào AWS Settings → **Activate advanced features** để được chọn region.
- Nếu account dùng **Free plan** (credit) mà có dịch vụ báo bị chặn, có thể nâng lên Paid plan; credit vẫn được trừ trước.

Kiểm tra account dùng được Singapore:

```powershell
aws ec2 describe-availability-zones --region ap-southeast-1 --query "AvailabilityZones[].ZoneName" --output text
# phải ra: ap-southeast-1a ap-southeast-1b ap-southeast-1c
```

**Chi phí:** `t3.micro` thuộc Free Tier. Khoản tốn chính là **NAT Gateway (~0,06 USD/giờ mỗi cái)**. Mỗi lần chạy pipeline Câu 2 sẽ tạo NAT **2 lần**: 1 lần trong taskcat test (tự xóa sau ~15 phút) và 1 lần cho stack thật. Làm xong phiên nào thì xóa ngay (mục 7). Tạo **AWS Budget** để có email cảnh báo.

### 5.1 Chuẩn bị máy và quyền truy cập

1. Cài công cụ và nạp PATH (mục 3). Bật đồng bộ giờ Windows (lệch giờ sẽ gây lỗi `SignatureDoesNotMatch`).
2. Trong IAM tạo **user riêng** (lab: gắn policy `AdministratorAccess`) → tab *Security credentials* → **Create access key** (loại CLI). Sau đó:
   ```powershell
   aws configure        # nhập key vừa tạo, region ap-southeast-1, output json
   aws sts get-caller-identity
   ```
3. Tạo SSH key `nt548-lab2` (mục 3).

### 5.2 Repo GitHub: chọn 1 trong 2 cách

| | Cách A: dùng chung repo `than8505/NT548-Lab2` | Cách B: fork / repo riêng của bạn |
|---|---|---|
| Quyền | Chủ repo thêm bạn làm collaborator **Admin** (để sửa Variables) + reviewer của environment `production` | Bạn là chủ |
| ID dùng cho OIDC | `github_owner_id=181867933`, `github_repo_id=1451096886` | Lấy bằng lệnh bên dưới |
| Việc thêm | Đổi Variables sang giá trị của account bạn sẽ **làm hỏng pipeline của người trước** (chỉ trỏ được 1 account), nên thống nhất trước | Tab **Actions** → bấm bật workflows (fork mặc định tắt). Tạo environment `production` + bật *Required reviewers* (chọn chính bạn). Repo nên để **public** (Câu 3 cần, và Code scanning hiển thị kết quả Checkov) |

Lấy ID cho cách B (thay `<owner>/<repo>`):

```powershell
Invoke-RestMethod https://api.github.com/repos/<owner>/<repo> | Select-Object @{n='repo_id';e={$_.id}}, @{n='owner_id';e={$_.owner.id}}
```

Clone repo về máy (cách B thì dùng URL repo của bạn):

```powershell
git clone https://github.com/<owner>/<repo>.git NT548-Lab2
cd NT548-Lab2
```

### 5.3 Câu 1: Terraform + GitHub Actions + Checkov

**Bước 1. Bootstrap** (tạo S3 state bucket `nt548-lab2-tfstate-<account_id>`, GitHub OIDC provider, IAM role):

```powershell
cd cau1-terraform/bootstrap
terraform init
terraform apply -var="github_repo=<owner>/<repo>" -var="aws_region=ap-southeast-1" -var="github_owner_id=<owner_id>" -var="github_repo_id=<repo_id>"
terraform output
cd ../..
```

- Account đã có GitHub OIDC provider từ trước → thêm `-var="create_github_oidc_provider=false"`.
- File `terraform.tfstate` của bootstrap **chỉ nằm trên máy bạn** (bị `.gitignore`). Đừng xóa, cần nó để `terraform destroy` bootstrap ở cuối lab.

**Bước 2. GitHub Variables:** Settings → Secrets and variables → Actions → **Variables**. Tạo 5 biến như bảng mục 4.1:

| Variable | Giá trị |
|---|---|
| `AWS_REGION` | `ap-southeast-1` |
| `AWS_ROLE_ARN` | output `github_actions_role_arn` |
| `TF_STATE_BUCKET` | output `state_bucket` |
| `ALLOWED_SSH_CIDR` | IP của bạn + `/32` (`curl.exe -s https://checkip.amazonaws.com`). Chỉ đặt 1 lần, vì sau đó dùng SSM |
| `SSH_PUBLIC_KEY` | nội dung file: `Get-Content "$env:USERPROFILE\.ssh\nt548-lab2.pub"` |

Kiểm tra lại environment **`production`** có *Required reviewers* là bạn.

**Bước 3. Chạy pipeline**, chọn 1 trong 2 cách:
- **Qua Pull Request** (minh chứng đẹp nhất): tạo nhánh → sửa nhẹ 1 file trong `cau1-terraform/` (ví dụ thêm tag) → push → mở PR vào `main` → xem Checkov / fmt-validate / plan + comment plan trong PR → Merge → job **Terraform apply** chờ duyệt → *Review deployments* → **Approve**.
  ```powershell
  git checkout -b feature/cau1-test
  # sửa 1 file trong cau1-terraform/ rồi:
  git commit -am "Cau 1: test pipeline"
  git push -u origin feature/cau1-test
  ```
- **Chạy tay:** Actions → *Cau 1 - Terraform CI/CD* → **Run workflow** → `action = apply` → Approve.

Lỗi `Not authorized to perform sts:AssumeRoleWithWebIdentity` → kiểm tra lại owner/repo ID ở bước 1 (mục 8, lỗi #14).

**Bước 4. Kiểm tra:** xem Summary của job apply để lấy `public_ec2_id`, `private_ec2_private_ip`, `nat_public_ip`. Thêm vào `~/.ssh/config` (mẫu như mục 6, đặt tên `lab2-bastion` / `lab2-private`, user `ec2-user`), rồi chạy:

```powershell
ssh lab2-bastion "hostname -I; curl -s https://checkip.amazonaws.com"   # ra public IP của bastion
ssh lab2-private "hostname -I; curl -s https://checkip.amazonaws.com"   # ra nat_public_ip
```

Chụp minh chứng: tab Actions (các job xanh), comment plan trong PR, artifact `checkov-report`, Security → Code scanning, VPC / Subnet / Route table / NAT / EC2 / SG trên Console.

**Bước 5. Xóa:** Actions → Run workflow → `action = destroy` → Approve.

### 5.4 Câu 2: CloudFormation + CodeBuild + CodePipeline

**Bước 1. Import key pair** (tên phải trùng `KeyName` trong `config/prod.json`):

```powershell
aws ec2 import-key-pair --key-name nt548-lab2-cfn --public-key-material fileb://$env:USERPROFILE/.ssh/nt548-lab2.pub --region ap-southeast-1
```

**Bước 2. Sửa `cau2-cloudformation/config/prod.json`:** đổi `AllowedSSHCidr` thành IP của bạn `/32`, giữ `KeyName` là `nt548-lab2-cfn`. Commit lên GitHub:

```powershell
git add cau2-cloudformation/config/prod.json
git commit -m "Cau 2: tham so cho account moi"
git push origin main
```

**Bước 3. Tạo stack pipeline** (khoảng 2–3 phút):

```powershell
aws cloudformation deploy --stack-name nt548-lab2-pipeline --template-file cau2-cloudformation/pipeline/pipeline.yaml --capabilities CAPABILITY_IAM --region ap-southeast-1 --parameter-overrides RepositoryName=nt548-lab2 BranchName=main EnableTaskcat=true EnableManualApproval=true
aws cloudformation describe-stacks --stack-name nt548-lab2-pipeline --region ap-southeast-1 --query "Stacks[0].Outputs" --output table
```

Nếu `deploy` báo `charmap codec` → có ký tự không phải ASCII trong `pipeline.yaml` (mục 8, lỗi #4).

**Bước 4. Đẩy code lên CodeCommit:** cấu hình remote + credential helper như sau, rồi push:

```powershell
git remote add codecommit https://git-codecommit.ap-southeast-1.amazonaws.com/v1/repos/nt548-lab2
cmd /c 'git config --local credential.https://git-codecommit.ap-southeast-1.amazonaws.com.helper ""'
git config --local --add credential.https://git-codecommit.ap-southeast-1.amazonaws.com.helper '!aws codecommit credential-helper $@'
git config --local credential.https://git-codecommit.ap-southeast-1.amazonaws.com.UseHttpPath true
git push codecommit main
```

Push xong, EventBridge tự kích hoạt pipeline.

**Bước 5. Theo dõi pipeline** (CodePipeline → `nt548-lab2-pipeline`, tổng khoảng 25–30 phút):
- *Source* → *Validate*: cfn-lint + package khoảng 2 phút, rồi taskcat khoảng 15 phút (deploy thử rồi tự xóa).
- *Approve* → bấm **Review → Approve**.
- *Deploy*: tạo stack `nt548-lab2-cfn-infra` khoảng 5 phút.

Xem tiến trình bằng lệnh:

```powershell
aws codepipeline get-pipeline-state --name nt548-lab2-pipeline --region ap-southeast-1 --query "stageStates[].[stageName,latestExecution.status]" --output table
```

**Bước 6. Kiểm tra:** lấy ID và IP bằng lệnh `describe-instances` ở mục 6, điền vào `cfn-bastion` / `cfn-private` trong `~/.ssh/config`, rồi chạy 2 lệnh `ssh` ở mục 6. So sánh với IP NAT:

```powershell
aws ec2 describe-nat-gateways --region ap-southeast-1 --filter Name=state,Values=available --query "NatGateways[].NatGatewayAddresses[0].PublicIp" --output text
```

Chụp minh chứng: danh sách ở mục 10.

**Bước 7. Xóa:** `aws cloudformation delete-stack --stack-name nt548-lab2-cfn-infra --region ap-southeast-1`, rồi kiểm tra lại bằng các lệnh ở mục 7.


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

## 8. Các lỗi đã gặp & cách sửa

Các lỗi dưới đây là lỗi **đã gặp thật** khi làm Câu 1 và Câu 2. Những dòng có dấu 🔸 là lỗi chưa gặp nhưng **dễ gặp khi làm lại**. Lỗi nào đã sửa trong code thì có ghi commit, nên **bạn sẽ không gặp lại** nếu dùng code mới nhất. Lỗi nào thuộc máy hoặc tài khoản thì ghi cách xử lý.

Tra nhanh: bấm `Ctrl+F` và dán một đoạn thông báo lỗi bạn đang gặp.

### 8.1 Máy Windows, AWS CLI, PowerShell

| # | Hiện tượng (thông báo lỗi) | Nguyên nhân | Cách sửa |
|---|---|---|---|
| 1 | `aws : The term 'aws' is not recognized...` (tương tự với `terraform`, `session-manager-plugin`) | Mới cài bằng winget nhưng terminal VS Code đang mở vẫn giữ PATH cũ | Chạy lệnh nạp PATH ở mục 3, hoặc đóng hẳn VS Code rồi mở lại |
| 2 | Đăng nhập AWS Console báo **Bad request** | Cookie/phiên đăng nhập cũ bị lẫn (nhiều tài khoản AWS trên cùng trình duyệt) | Mở cửa sổ **InPrivate/Incognito** để đăng nhập, hoặc xóa cookie của `aws.amazon.com` |
| 3 | `An error occurred (SignatureDoesNotMatch)` hoặc `Signature expired` khi chạy bất kỳ lệnh `aws` nào | Đồng hồ Windows lệch giờ (lần đó lệch 7 tiếng do sai múi giờ). Chữ ký AWS phụ thuộc thời gian | Settings → Time & language → bật *Set time automatically* + *Set time zone automatically* (UTC+07:00) → **Sync now**. Thử lại `aws sts get-caller-identity` |
| 4 | `'charmap' codec can't decode/encode byte ...` khi chạy `aws cloudformation deploy --template-file ...` | AWS CLI trên Windows đọc file bằng bảng mã cp1252, không đọc được tiếng Việt có dấu | **Giữ `pipeline.yaml` và các template chỉ có ký tự ASCII** (comment viết không dấu). Đã sửa, commit `8a7659b`. Kiểm tra trước khi deploy: `Select-String -Path cau2-cloudformation\pipeline\pipeline.yaml -Pattern '[^\x00-\x7F]'` (không ra gì là OK) |
| 5 | `'charmap' codec can't encode character ...` khi chuyển kết quả `aws logs tail ...` vào file (`> file.txt` / `Out-File`) | Log CodeBuild có ký tự Unicode, AWS CLI ghi ra pipe bằng cp1252 | Đừng chuyển vào file, cho in thẳng ra terminal rồi copy. Hoặc xem log trên Console (CodeBuild → Build history → Build logs) |
| 6 🔸 | Lệnh nhiều dòng trong README bị lỗi trên PowerShell | README viết theo cú pháp bash (xuống dòng bằng `\`). PowerShell xuống dòng bằng dấu backtick `` ` `` | Gộp lệnh thành 1 dòng, hoặc thay `\` cuối dòng bằng `` ` ``. Các lệnh trong HANDOFF đã viết sẵn cho PowerShell |
| 7 | Lệnh `git config ... helper ""` không có tác dụng | **PowerShell 5.1 tự bỏ tham số chuỗi rỗng `""`** khi gọi chương trình ngoài | Chạy qua `cmd /c '...'` (như mục 5.4 bước 4) |

### 8.2 GitHub, Git

| # | Hiện tượng | Nguyên nhân | Cách sửa |
|---|---|---|---|
| 8 | `git push` bị chặn: `GH013: Repository rule violations found ... Push cannot contain secrets ... Stripe API Key` | Mã nguồn gốc của app (Câu 3) có Stripe test key viết cứng trong `payment/src/test/setup.ts`. GitHub Push Protection chặn | Đã sửa trong commit đầu: đọc từ biến môi trường `STRIPE_TEST_KEY`, test gọi Stripe thật bị `skip` nếu không có key. Nếu gặp lại với file khác: xóa secret khỏi file → `git commit --amend` (secret nằm ở commit cuối) → push lại. **Không** bấm "allow secret" |
| 9 | File `.sh` báo `Permission denied` khi chạy trên EC2/CodeBuild | Commit từ Windows không giữ quyền thực thi | `git add --chmod=+x <file>.sh` rồi commit. Repo đã có `.gitattributes` (`* text=auto eol=lf`) để tránh lỗi `\r` cuối dòng |
| 10 | Lỡ commit file log tạm (`cfnlint-log.txt`) | Chạy lệnh ghi log trong thư mục repo rồi `git add .` | `git rm --cached <file>` → commit (commit `b9e75b0`). Nên `git status` trước khi `git add .` |
| 11 | Push lên CodeCommit bật cửa sổ **Git Credential Manager** đòi username/password | GCM của Git for Windows chặn trước credential helper của AWS CLI | Cấu hình helper riêng cho host CodeCommit (mục 5.4 bước 4). Không cần tạo "HTTPS Git credentials" |

### 8.3 Câu 1: GitHub Actions, Terraform, Checkov

| # | Hiện tượng | Nguyên nhân | Cách sửa |
|---|---|---|---|
| 12 | Job **Checkov** fail ở 4 check: `CKV_AWS_394`, `CKV_AWS_24`, `CKV2_AWS_5` (×2) | `CKV_AWS_394`: lấy danh sách AZ bằng data source. `CKV_AWS_24` (SSH từ 0.0.0.0/0) và `CKV2_AWS_5` (SG không gắn vào tài nguyên) là **báo nhầm**: nguồn SSH là SG của bastion, và SG được gắn qua biến module nên Checkov không lần ra | Commit `6c7784c`: ghim AZ trong `cau1-terraform/main.tf` (`["${var.aws_region}a", "${var.aws_region}b"]`), thêm `#checkov:skip=<ID>:<lý do>` trong `modules/security-groups/main.tf`. Nguyên tắc: **chỉ skip khi giải thích được là báo nhầm**, còn lại phải sửa code |
| 13 | Upload SARIF báo cảnh báo CodeQL Action v3 sắp bị ngừng | `github/codeql-action` v3 đã deprecated | Đã nâng lên `upload-sarif@v4`. Repo private không có GHAS thì bước này lỗi nhưng đã đặt `continue-on-error: true`, nên vẫn xem report trong artifact `checkov-report` |
| 14 | Job plan/apply: `Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity` | IAM role chỉ tin `sub` dạng `repo:owner/repo:*`, nhưng GitHub giờ gửi dạng **immutable ID**: `repo:than8505@181867933/NT548-Lab2@1451096886:pull_request` | Commit `45866d3`: bootstrap nhận thêm `github_owner_id`, `github_repo_id` và tin cả 2 dạng. **Cách tìm nguyên nhân:** CloudTrail → Event history → lọc *Event name* = `AssumeRoleWithWebIdentity` → mở event lỗi, xem trường `sub` thật GitHub gửi. Cũng kiểm tra variable `AWS_ROLE_ARN` và `permissions: id-token: write` |
| 15 🔸 | Bootstrap báo `EntityAlreadyExists: Provider with url https://token.actions.githubusercontent.com already exists` | Account đã có GitHub OIDC provider (mỗi account chỉ có 1) | Thêm `-var="create_github_oidc_provider=false"` |
| 16 | Bấm Approve trong GitHub Environment báo *"There was a problem approving one of the gates"* | Lỗi giao diện GitHub khi bấm nhiều lần/trang cũ | Tải lại trang (F5) và bấm **Approve and deploy** đúng **1 lần**. Kiểm tra bạn có trong *Required reviewers* |
| 17 🔸 | Job apply bị bỏ qua (skipped) dù đã merge | Plan không có thay đổi (`has_changes=false`), hoặc chạy dispatch với `action=plan` | Đúng thiết kế. Muốn apply lại: Run workflow → `action = apply` |

### 8.4 Truy cập EC2 (SSH, Session Manager)

| # | Hiện tượng | Nguyên nhân | Cách sửa |
|---|---|---|---|
| 18 | `ssh: connect to host <IP> port 22: Connection timed out` | IP public của máy bạn **đã đổi** (đổi wifi/4G), không còn khớp `ALLOWED_SSH_CIDR` / `AllowedSSHCidr` | Dùng **SSM Session Manager** (mục 6). Không cần mở port 22 theo IP nữa. Kiểm tra IP hiện tại: `curl.exe -s https://checkip.amazonaws.com` |
| 19 | `SessionManagerPlugin is not found` | Chưa cài plugin hoặc PATH chưa nạp | `winget install -e --id Amazon.SessionManagerPlugin` → nạp PATH (mục 3) |
| 20 | `ValidationException ... target ... failed to satisfy constraint ... ^[a-zA-Z0-9_:-]{1,400}$` | `HostName` trong `~/.ssh/config` còn placeholder (`<ID_PUBLIC_EC2>`) thay vì instance ID | Thay bằng ID thật, ví dụ `(Get-Content "$env:USERPROFILE\.ssh\config") -replace '<ID_PUBLIC_EC2>', 'i-0123...' \| Set-Content "$env:USERPROFILE\.ssh\config" -Encoding ascii` |
| 21 🔸 | `TargetNotConnected` / SSM không thấy máy | EC2 mới khởi động (đợi 2–3 phút), hoặc thiếu IAM role SSM, hoặc máy private không ra được Internet (NAT hỏng) | Kiểm tra Systems Manager → Fleet Manager máy có **Online** không. Máy private được truy cập qua `ProxyJump` bastion nên không phụ thuộc SSM của máy đó |
| 22 🔸 | `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!` | Dựng lại hạ tầng, IP private hoặc instance ID cũ trùng với máy mới | `ssh-keygen -R <host>` (ví dụ `ssh-keygen -R 10.10.2.184`) rồi ssh lại, gõ `yes` |
| 23 🔸 | `Permission denied (publickey)` | Sai user (Amazon Linux là `ec2-user`, Ubuntu ở Câu 3 là `ubuntu`), sai `IdentityFile`, hoặc EC2 tạo với key pair khác | Kiểm tra `~/.ssh/config`. Câu 2: key pair trên AWS phải là `nt548-lab2-cfn`, import từ chính `nt548-lab2.pub` |

### 8.5 Câu 2: CodeBuild (cfn-lint, taskcat)

| # | Hiện tượng | Nguyên nhân | Cách sửa |
|---|---|---|---|
| 24 | Build `cfn-lint`: `ModuleNotFoundError: No module named 'junit_xml'`, sau đó Report group báo lỗi đọc XML (EOF) | Xuất JUnit cần extra `[junit]`. Khi cfn-lint crash thì file XML rỗng | Commit `f76815e`: cài `"cfn-lint[junit]>=1.20,<2"`. Build chỉ fail khi exit code của cfn-lint chứa bit **2 (error)**; warning (4) và informational (8) chỉ hiện trong report |
| 25 | cfn-lint báo `I3011` cho các nested stack (thiếu DeletionPolicy/UpdateReplacePolicy) | Thông báo dạng informational | Commit `f76815e`: thêm `DeletionPolicy: Delete` + `UpdateReplacePolicy: Delete` cho 3 nested stack trong `templates/main.yaml` |
| 26 | Build `taskcat`: `ModuleNotFoundError: No module named 'pkg_resources'` | `setuptools` >= 81 đã bỏ `pkg_resources`, nhưng taskcat vẫn dùng | Commit `8bdcba0`: `pip install "setuptools<81" taskcat` trong `buildspecs/taskcat.yml` |
| 27 | taskcat: `PermanentRedirect ... The bucket you are attempting to access must be addressed using the specified endpoint` | taskcat tạo bucket ở region khác với region test | Commit `be304d2`: `s3_regional_buckets: true` trong `.taskcat.yml` |
| 28 | taskcat: `ProfileNotFound: The config profile (default) could not be found` ở bước `taskcat test clean` | CodeBuild dùng IAM role, không có profile `default` | Commit `be304d2`: bỏ `taskcat test clean` (`taskcat test run` đã tự xóa stack test). Post-build chỉ liệt kê stack `tCaT-*` còn sót |
| 29 🔸 | taskcat `CREATE_FAILED` | Quota Elastic IP/NAT, AZ không có `t3.micro`, hoặc lỗi template | CloudFormation → tìm stack `tCaT-...` → tab **Events**, đọc dòng `CREATE_FAILED` đầu tiên (là nguyên nhân gốc) |

### 8.6 Câu 2: CodePipeline, Deploy CloudFormation

| # | Hiện tượng | Nguyên nhân | Cách sửa |
|---|---|---|---|
| 30 | Stage Deploy fail: `... CloudFormationDeployRole ... is not authorized to perform: iam:PassRole on resource ...CloudFormationDeployRole...` | Stack cha tạo nested stack **bằng chính role của nó**, nên role phải được phép PassRole cho chính nó | Commit `8a7659b`: thêm resource `CloudFormationDeployRolePassSelf` (`AWS::IAM::RolePolicy`) trong `pipeline/pipeline.yaml`. Sau khi sửa: chạy lại `aws cloudformation deploy` cho **stack pipeline** (mục 5.4 bước 3), rồi xử lý #31 |
| 31 | Stack `nt548-lab2-cfn-infra` ở trạng thái `ROLLBACK_COMPLETE`, Retry vẫn lỗi | Stack tạo lần đầu bị lỗi thì không update được, chỉ xóa được | `aws cloudformation delete-stack --stack-name nt548-lab2-cfn-infra --region ap-southeast-1` → `aws cloudformation wait stack-delete-complete ...` → CodePipeline → **Retry** stage Deploy (hoặc *Release change*) |
| 32 🔸 | Stage Source fail | Chưa push nhánh `main` lên CodeCommit, hoặc sai `RepositoryName` | `git push codecommit main`, kiểm tra tên repo trong output stack pipeline |
| 33 🔸 | Sửa `pipeline.yaml` rồi push CodeCommit nhưng pipeline không đổi | **Stack pipeline không tự cập nhật từ CodeCommit**. Pipeline chỉ deploy các file trong `templates/` | Mỗi lần sửa `pipeline.yaml` phải chạy lại `aws cloudformation deploy` cho stack `nt548-lab2-pipeline` |

### 8.7 Lệnh chẩn đoán hay dùng

```powershell
# Trạng thái từng stage của pipeline
aws codepipeline get-pipeline-state --name nt548-lab2-pipeline --region ap-southeast-1 --query "stageStates[].[stageName,latestExecution.status]" --output table

# Lý do stack CloudFormation lỗi (các event FAILED gần nhất)
aws cloudformation describe-stack-events --stack-name nt548-lab2-cfn-infra --region ap-southeast-1 --query "StackEvents[?contains(ResourceStatus,'FAILED')].[Timestamp,LogicalResourceId,ResourceStatusReason]" --output table

# Log CodeBuild (in thẳng ra terminal, KHÔNG chuyển vào file - xem #5)
aws logs tail /aws/codebuild/<ten-project> --since 1h --region ap-southeast-1

# Lỗi OIDC của GitHub Actions
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity --max-results 5 --region ap-southeast-1
```

Khi hỏi trợ lý AI về lỗi: gửi **nguyên văn thông báo lỗi** (copy text, không chỉ ảnh), kèm lệnh vừa chạy và số mục liên quan trong file này.


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
Nếu tôi làm lại trên AWS account riêng: account phải dùng được region ap-southeast-1 (đăng ký kiểu "advanced"), tôi làm theo mục 5 của HANDOFF.md
(bootstrap OIDC với github_owner_id/github_repo_id, GitHub Variables, import key pair nt548-lab2-cfn, sửa config/prod.json, deploy pipeline.yaml, push CodeCommit).
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
