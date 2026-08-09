# Zweig - TODO

This file lists the next steps to make `zweig` a fully testable project.

## 1. Create the Dockerized Test Environment

- [ ] test all commands inside the docker container

## 2. Create the Test Suite

- [ ] Create test files for each module (e.g., `tests/core.bats`, `tests/lifecycle.bats`).
- [ ] Write test cases for all commands, covering both success and failure scenarios.

## 4. Integrate Testing into CI/CD

- [ ] Create a new GitHub Actions workflow (e.g., `.github/workflows/test.yml`).
- [ ] Configure the workflow to run on pull requests and pushes to `main`.
- [ ] Add a job to the workflow to build the test container and run the tests using `make test`.

## 5. Update the Documentation

- [ ] Make `Makefile` self-documenting.
