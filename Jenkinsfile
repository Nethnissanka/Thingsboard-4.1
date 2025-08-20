pipeline {
    agent any

    parameters {
        string(name: 'TB_VERSION', defaultValue: '4.2.0', description: 'Enter the ThingsBoard version to upgrade (e.g., 4.2.1)')
    }

    environment {
        TB_DOCKER_PATH = "/home/nethmi/thingsboard"
        BACKUP_PATH = "/home/nethmi/tb-backups"
        SERVER_COMPOSE = "docker-compose.yml"
        UPGRADE_COMPOSE = "docker-compose.upgrade.yml"

        PACKAGE_REPO  = "https://github.com/thingsboard/thingsboard/releases/download"
        CURRENT_VERSION = ""
        TARGET_VERSION = ""
        UPGRADE_REQUIRED = "false"
    }

    stages {
        stage('Checkout') {
            steps {
                echo '📥 Checking out repository...'
                checkout scm
            }
        }

        stage('Init Variables') {
            steps {
                script {
                    env.IMAGE_NAME = "thingsboard:${params.TB_VERSION}"
                    env.NEW_CONTAINER_NAME = "thingsboard-${params.TB_VERSION}"
                    env.TARGET_VERSION = params.TB_VERSION
                }
            }
        }

        stage('Detect Current Installed Version') {
            steps {
                script {
                    echo '🔍 Detecting current running ThingsBoard container...'
                    def containerList = sh(script: "docker ps --format '{{.Names}}' | grep '^thingsboard-' || true", returnStdout: true).trim()
                    if (containerList) {
                        def currentContainer = containerList.split("\\n")[0].trim()
                        def currentImage = sh(script: "docker inspect ${currentContainer} --format '{{ index .Config.Image }}'", returnStdout: true).trim()
                        def currentTag = currentImage.split(":")[1]

                        echo "📦 Current running container: ${currentContainer}"
                        echo "📦 Current running image: ${currentImage}"
                        echo "📦 Current version: ${currentTag}"

                        env.CURRENT_CONTAINER_NAME = currentContainer
                        env.CURRENT_IMAGE_NAME = currentImage
                        env.CURRENT_VERSION = currentTag
                        env.ROLLBACK_IMAGE = "thingsboard:rollback-${currentTag}"
                    } else {
                        echo "⚠️ No running ThingsBoard container found"
                        env.CURRENT_CONTAINER_NAME = ""
                        env.CURRENT_VERSION = "none"
                        env.CURRENT_IMAGE_NAME = ""
                        env.ROLLBACK_IMAGE = ""
                    }
                }
            }
        }

        stage('Fetch Latest GitHub Version') {
            steps {
                script {
                    def apiOutput = sh(
                        script: "curl -s https://api.github.com/repos/thingsboard/thingsboard/releases/latest",
                        returnStdout: true
                    ).trim()
                    def matcher = apiOutput =~ /"tag_name":\s*"v(.*?)"/
                    def latestVersion = matcher ? matcher[0][1] : "unknown"
                    env.LATEST_VERSION = latestVersion
                    echo "📦 Latest Available Version on GitHub: ${latestVersion}"
                }
            }
        }

        // stage('Compare Versions') {
        //     steps {
        //         script {
        //             echo '🔍 Comparing current version with target release...'
        //             echo "📦 Current: ${env.CURRENT_VERSION} → Target: ${env.TARGET_VERSION}"
        //             echo "📦 Latest: ${env.LATEST_VERSION}"
        //             echo "Target: ${env.TARGET_VERSION}"
        //             echo "Current: ${env.CURRENT_VERSION}"
        //             echo "TB: ${env.TB_VERSION}"

        //             if (env.CURRENT_VERSION == env.TARGET_VERSION) {
        //                 echo "✅ ThingsBoard is already up to date (v${env.CURRENT_VERSION})"
        //                 env.UPGRADE_REQUIRED = "false"
        //             } else {
        //                 echo "⬆️ Upgrade required: ${env.CURRENT_VERSION} ➜ ${env.TARGET_VERSION}"
        //                 env.UPGRADE_REQUIRED = "true"
        //             }
        //         }
        //     }
        // }
        

        stage('Compare Versions') {
            steps {
                script {
                    echo '🔍 Comparing current version with target release...'
                    echo "📦 Current: ${env.CURRENT_VERSION} → Target: ${env.TARGET_VERSION}"
                    echo "📦 Latest on GitHub: ${env.LATEST_VERSION}"

                    if (env.CURRENT_VERSION == env.TARGET_VERSION) {
                        echo "✅ ThingsBoard is already up to date (v${env.CURRENT_VERSION})"
                        env.UPGRADE_REQUIRED = "false"
                    } else {
                        echo "⬆️ Upgrade required: ${env.CURRENT_VERSION} ➜ ${env.TARGET_VERSION}"
                        env.UPGRADE_REQUIRED = "true"
                    }
                }
            }
        }


        stage('Skip Upgrade') {
            when { expression { env.UPGRADE_REQUIRED == "false" } }
            steps { echo "✅ Skipping upgrade — Already latest version." }
        }

        stage('Download RPM') {
            when { expression { env.UPGRADE_REQUIRED == "true" } }
            steps {
                script {
                    echo "📥 Downloading ThingsBoard RPM package..."
                    def rpmUrl = "${PACKAGE_REPO}/v${env.TARGET_VERSION}/thingsboard-${env.TARGET_VERSION}.rpm"
                    echo "📥 RPM URL: ${rpmUrl}"
                    sh """
                        curl -L -o thingsboard-${env.TARGET_VERSION}.rpm ${rpmUrl}
                        ls -lh thingsboard-*.rpm
                    """
                }
            }
        }

        stage('Backup Current Image') {
            when { expression { env.UPGRADE_REQUIRED == "true" && env.CURRENT_IMAGE_NAME != "" } }
            steps {
                echo "📦 Tagging current image for rollback: ${env.ROLLBACK_IMAGE}"
                sh "docker tag ${env.CURRENT_IMAGE_NAME} ${env.ROLLBACK_IMAGE}"
            }
        }

        // stage('Stop and Remove Old Container') {
        //     when { expression { env.UPGRADE_REQUIRED == "true" && env.CURRENT_CONTAINER_NAME != "" } }
        //     steps {
        //         echo "🛑 Stopping container ${env.CURRENT_CONTAINER_NAME}"
        //         sh """
        //             docker stop ${env.CURRENT_CONTAINER_NAME} || true
        //             docker rm ${env.CURRENT_CONTAINER_NAME} || true
        //         """
        //     }
        // }

        // stage('Start New Version with Docker Compose') {
        //     when { expression { env.UPGRADE_REQUIRED == "true" } }
        //     steps {
        //         echo "🚀 Launching ThingsBoard v${env.TARGET_VERSION} using Docker Compose"
        //         sh """
        //             TB_VERSION=${env.TARGET_VERSION} docker compose down || true
        //             TB_VERSION=${env.TARGET_VERSION} docker compose up -d
        //         """
        //     }
        // }

        stage('Verify Deployment') {
            // when { expression { env.UPGRADE_REQUIRED == "true" } }
            steps {
                script {
                    echo "🔍 Verifying ThingsBoard is running..."
                    // Retry for up to 5 minutes
                    def maxRetries = 10
                    def success = false
                    for (int i=1; i<=maxRetries; i++) {
                        def code = sh(script: "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/login", returnStdout: true).trim()
                        if (code == "200") {
                            echo "✅ ThingsBoard is up and responding (HTTP 200)"
                            success = true
                            break
                        } else {
                            echo "⏳ Waiting for ThingsBoard to start... (Attempt ${i})"
                            sleep 30
                        }
                    }
                    if (!success) { error "❌ Upgrade failed — ThingsBoard not responding after timeout." }
                }
            }
        }
    }

    post {
        success {
            script {
                echo "✅ Upgrade pipeline completed successfully!"
                if (env.UPGRADE_REQUIRED == "true") {
                    echo "🎉 ThingsBoard upgraded from v${env.CURRENT_VERSION} to v${env.TARGET_VERSION} successfully!"
                } else {
                    echo "✅ No upgrade needed. Still running v${env.CURRENT_VERSION}."
                }
            }
        }
        failure {
            script {
                echo "❌ Upgrade failed. Starting rollback..."
                // if (env.ROLLBACK_IMAGE && env.CURRENT_CONTAINER_NAME != "") {
                //     echo "🔁 Restoring from image: ${env.ROLLBACK_IMAGE}"
                //     sh """
                //         docker stop ${env.NEW_CONTAINER_NAME} || true
                //         docker rm ${env.NEW_CONTAINER_NAME} || true
                //         docker run -d --name ${env.CURRENT_CONTAINER_NAME} -p 8080:8080 ${env.ROLLBACK_IMAGE}
                //     """
                //     echo "✅ Rollback complete. ThingsBoard is back to v${env.CURRENT_VERSION}"
                // } else {
                //     echo "⚠️ No backup image available to rollback."
                // }
                // error "❌ Upgrade failed and rollback was triggered."
            }
        }
    }
}

