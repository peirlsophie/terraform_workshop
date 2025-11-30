Why do we need Terraform Cloud (or another backend) when we use CI/CD?

Because CI/CD is stateless and Terraform files provide tracking what resources already exist, what should be created or destroyed, resource IDs, dependencies etc.
Without the backend the CI/CD runner would create every AWS infrastructure for every run.
