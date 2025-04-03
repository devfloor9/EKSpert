1. Project Structure Setup
Start with this directory structure:

```bash
EKSpert/
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars
├── versions.tf
├── modules/
│   ├── networking/
│   ├── eks/
│   ├── monitoring/
│   └── logging/
└── environments/
    ├── dev/
    ├── staging/
    └── production/
```
