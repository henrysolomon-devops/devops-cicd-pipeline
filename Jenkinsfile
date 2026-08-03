// The whole CI/CD pipeline for v7, replacing what deploy.yml and
// promote.yml used to do together in v6. This runs entirely on the
// built-in node (no separate agent, see PROJECT_PLAN.md's v7 notes) and
// talks to the app server's k3s cluster directly through the
// kubeconfig install-jenkins.yml placed at /var/lib/jenkins/.kube/config -
// no GitOps agent, no PR-based promotion, just a straightforward push
// pipeline with a real approval click before staging and production.

pipeline {
    agent any

    options {
        // Two pushes to main close together shouldn't both try to
        // deploy at the same time and step on each other's helm release.
        disableConcurrentBuilds()
    }

    environment {
        IMAGE_NAME = "ghcr.io/henrysolomon-devops/devops-cicd-pipeline"
        // Where install-jenkins.yml copied the app server's kubeconfig -
        // every kubectl/helm call below reads it from here.
        KUBECONFIG = "/var/lib/jenkins/.kube/config"
    }

    stages {
        stage('Read app version') {
            steps {
                // Same split as v6: VERSION is the human-readable string
                // shown on the dashboard, bumped by hand before a
                // release. The commit SHA (used below as the image tag)
                // is what actually guarantees every build is unique.
                script {
                    env.APP_VERSION = readFile('VERSION').trim()
                    echo "Building version ${env.APP_VERSION}, commit ${env.GIT_COMMIT}"
                }
            }
        }

        stage('Build and push image') {
            steps {
                script {
                    def appImage = docker.build(
                        "${IMAGE_NAME}:${env.GIT_COMMIT}",
                        "--build-arg APP_VERSION=${env.APP_VERSION} -f docker/Dockerfile ."
                    )
                    // ghcr-credentials is the one credential JCasC
                    // defines (see jenkins/jenkins.yaml) - a GitHub PAT
                    // scoped to packages:write, since Jenkins has no
                    // access to GitHub Actions' automatic GITHUB_TOKEN.
                    docker.withRegistry("https://ghcr.io", "ghcr-credentials") {
                        appImage.push()
                    }
                }
            }
        }

        stage('Deploy to dev') {
            // No approval gate here on purpose, matching the rule
            // that's held since v4: dev always deploys the moment a
            // build finishes.
            steps {
                sh """
                    helm upgrade --install devops-pipeline helm/devops-pipeline \
                      -f helm/devops-pipeline/values-dev.yaml \
                      --set image.tag=${env.GIT_COMMIT} \
                      -n dev
                    kubectl rollout status deployment/devops-pipeline -n dev --timeout=120s
                """
            }
        }

        stage('Approve staging') {
            steps {
                // This is the real approval step - the pipeline sits
                // here until someone clicks Proceed in the Jenkins UI,
                // the same job the "staging" GitHub Environment used to
                // do back in v4/v5.1, and the staging promotion PR did
                // in v6.
                input message: "Deploy ${env.GIT_COMMIT} to staging?", ok: "Deploy"
            }
        }

        stage('Deploy to staging') {
            steps {
                sh """
                    helm upgrade --install devops-pipeline helm/devops-pipeline \
                      -f helm/devops-pipeline/values-staging.yaml \
                      --set image.tag=${env.GIT_COMMIT} \
                      -n staging
                    kubectl rollout status deployment/devops-pipeline -n staging --timeout=120s
                """
            }
        }

        stage('Approve production') {
            steps {
                input message: "Deploy ${env.GIT_COMMIT} to production?", ok: "Deploy"
            }
        }

        stage('Deploy to production') {
            steps {
                sh """
                    helm upgrade --install devops-pipeline helm/devops-pipeline \
                      -f helm/devops-pipeline/values-production.yaml \
                      --set image.tag=${env.GIT_COMMIT} \
                      -n production
                    kubectl rollout status deployment/devops-pipeline -n production --timeout=120s
                """
            }
        }
    }
}
