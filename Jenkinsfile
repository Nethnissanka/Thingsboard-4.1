pipeline {
    agent any
    
    parameters {
        string(
            name: 'TB_VERSION',
            defaultValue: '',
            description: 'ThingsBoard version to upgrade to (e.g., 4.3.0, 4.4.0). Leave empty for latest'
        )
        choice(
            name: 'ENVIRONMENT',
            choices: ['development', 'staging', 'production'],
            description: 'Target environment'
        )
        booleanParam(
            name: 'SKIP_BACKUP',
            defaultValue: false,
            description: 'Skip configuration backup (not recommended for production)'
        )
        booleanParam(
            name: 'AUTO_PROCEED',
            defaultValue: false,
            description: 'Automatically proceed without manual confirmation'
        )
        booleanParam(
            name: 'FORCE_UPGRADE',
            defaultValue: false,
            description: 'Force upgrade even if versions match'
        )
    }
    
    environment {
        // 🔧 Customize these paths based on your setup
        TB_DOCKER_PATH = "/home/nethmi/thingsboard"
        BACKUP_PATH = "/home/nethmi/tb-backups"
        SERVER_COMPOSE = "docker-compose.yml"
        UPGRADE_COMPOSE = "docker-compose.upgrade.yml"
        PACKAGE_REPO = "https://github.com/thingsboard/thingsboard/releases/download"
        
        // Will be set dynamically
        CURRENT_VERSION = ""
        TARGET_VERSION = ""
        UPGRADE_REQUIRED = "false"
    }
    
    stages {
        stage('Pre-flight Checks') {
            steps {
                script {
                    echo "🔍 Starting ThingsBoard upgrade process"
                    echo "🎯 Target environment: ${params.ENVIRONMENT}"
                    
                    // Check if ThingsBoard container exists
                    def containerExists = sh(
                        script: "docker ps -a --format '{{.Names}}' | grep -E '^(tb-server|thingsboard-.*)\$' | head -1",
                        returnStdout: true
                    ).trim()
                    
                    if (!containerExists) {
                        error("❌ No ThingsBoard container found! Expected 'tb-server' or 'thingsboard-*'")
                    }
                    
                    echo "✅ Found ThingsBoard container: ${containerExists}"
                    env.CONTAINER_NAME = containerExists
                }
            }
        }
        
        stage('Detect Current Version') {
            steps {
                script {
                    echo '🔍 Detecting current ThingsBoard version...'
                    
                    try {
                        // Method 1: Try to get from Docker image tag
                        def image = sh(
                            script: "docker inspect ${env.CONTAINER_NAME} --format '{{ index .Config.Image }}'",
                            returnStdout: true
                        ).trim()
                        
                        if (image.contains(":")) {
                            env.CURRENT_VERSION = image.split(":")[1]
                        } else {
                            env.CURRENT_VERSION = "unknown"
                        }
                        
                        // Method 2: Try to extract from container name if image tag is not informative
                        if (env.CURRENT_VERSION == "latest" || env.CURRENT_VERSION == "unknown") {
                            if (env.CONTAINER_NAME.contains("thingsboard-")) {
                                env.CURRENT_VERSION = env.CONTAINER_NAME.replace("thingsboard-", "")
                            }
                        }
                        
                    } catch (Exception e) {
                        echo "⚠️ Could not detect version from container: ${e.getMessage()}"
                        env.CURRENT_VERSION = "unknown"
                    }
                    
                    if (env.CURRENT_VERSION == "unknown" || !env.CURRENT_VERSION) {
                        echo "⚠️ Could not auto-detect current version. Please specify target version manually."
                        if (!params.TB_VERSION) {
                            error("❌ Cannot proceed without knowing current or target version!")
                        }
                    }
                    
                    echo "📦 Current version: ${env.CURRENT_VERSION}"
                }
            }
        }
        
        stage('Determine Target Version') {
            steps {
                script {
                    if (params.TB_VERSION?.trim()) {
                        // Manual version specified
                        env.TARGET_VERSION = params.TB_VERSION.trim()
                        echo "🔧 Manual version specified: ${env.TARGET_VERSION}"
                        
                        // Validate version format
                        if (!env.TARGET_VERSION.matches(/^\d+\.\d+\.\d+$/)) {
                            error("❌ Invalid version format. Expected format: x.y.z (e.g., 4.3.0)")
                        }
                    } else {
                        // Fetch latest version from GitHub
                        echo '🌐 Fetching latest release from GitHub...'
                        try {
                            def json = sh(
                                script: 'curl -s --max-time 30 https://api.github.com/repos/thingsboard/thingsboard/releases/latest',
                                returnStdout: true
                            ).trim()
                            
                            def matcher = json =~ /"tag_name":\s*"v([0-9.]+)"/
                            if (matcher) {
                                env.TARGET_VERSION = matcher[0][1]
                            } else {
                                error("❌ Could not parse latest version from GitHub API")
                            }
                        } catch (Exception e) {
                            error("❌ Failed to fetch latest version from GitHub: ${e.getMessage()}")
                        }
                        
                        echo "🌐 Latest available version: ${env.TARGET_VERSION}"
                    }
                }
            }
        }
        
        stage('Compare Versions') {
            steps {
                script {
                    echo '🔍 Comparing versions...'
                    echo "📦 Current: ${env.CURRENT_VERSION} → Target: ${env.TARGET_VERSION}"
                    
                    if (env.CURRENT_VERSION == env.TARGET_VERSION && !params.FORCE_UPGRADE) {
                        echo "✅ Already running target version ${env.TARGET_VERSION}"
                        env.UPGRADE_REQUIRED = "false"
                    } else if (params.FORCE_UPGRADE) {
                        echo "🔄 Force upgrade enabled - proceeding with upgrade"
                        env.UPGRADE_REQUIRED = "true"
                    } else {
                        echo "⬆️ Upgrade required: ${env.CURRENT_VERSION} ➜ ${env.TARGET_VERSION}"
                        env.UPGRADE_REQUIRED = "true"
                    }
                }
            }
        }
        
        stage('Skip Upgrade') {
            when {
                expression { env.UPGRADE_REQUIRED == "false" }
            }
            steps {
                echo "✅ No upgrade needed - already running ${env.TARGET_VERSION}"
            }
        }
        
        stage('Create Backup') {
            when {
                allOf {
                    expression { env.UPGRADE_REQUIRED == "true" }
                    not { params.SKIP_BACKUP }
                }
            }
            steps {
                script {
                    echo "💾 Creating backup before upgrade..."
                    
                    def timestamp = new Date().format('yyyyMMdd-HHmmss')
                    def backupDir = "${BACKUP_PATH}/${params.ENVIRONMENT}-${env.CURRENT_VERSION}-to-${env.TARGET_VERSION}-${timestamp}"
                    
                    sh """
                        # Create backup directory
                        mkdir -p ${backupDir}
                        
                        cd ${TB_DOCKER_PATH}
                        
                        # Backup configuration files
                        cp ${SERVER_COMPOSE} ${backupDir}/ 2>/dev/null || echo "⚠️ ${SERVER_COMPOSE} not found"
                        cp ${UPGRADE_COMPOSE} ${backupDir}/ 2>/dev/null || echo "⚠️ ${UPGRADE_COMPOSE} not found"
                        cp Dockerfile ${backupDir}/ 2>/dev/null || echo "⚠️ Dockerfile not found"
                        
                        # Backup container information
                        echo "Container: ${env.CONTAINER_NAME}" > ${backupDir}/container-info.txt
                        echo "Current Version: ${env.CURRENT_VERSION}" >> ${backupDir}/container-info.txt
                        echo "Target Version: ${env.TARGET_VERSION}" >> ${backupDir}/container-info.txt
                        echo "Backup Date: \$(date)" >> ${backupDir}/container-info.txt
                        
                        # Get current container configuration
                        if docker ps -a | grep -q "${env.CONTAINER_NAME}"; then
                            docker inspect ${env.CONTAINER_NAME} > ${backupDir}/container-inspect.json
                        fi
                        
                        # Backup any custom configuration files
                        find . -name "*.conf" -o -name "*.properties" -o -name "*.yml" -o -name "*.yaml" | while read file; do
                            cp "\$file" ${backupDir}/ 2>/dev/null || true
                        done
                        
                        echo "✅ Backup created at: ${backupDir}"
                    """
                    
                    env.BACKUP_DIR = backupDir
                }
            }
        }
        
        stage('Cleanup Old Files') {
            when {
                expression { env.UPGRADE_REQUIRED == "true" }
            }
            steps {
                script {
                    echo '🧹 Cleaning up old RPM files...'
                    sh """
                        cd ${TB_DOCKER_PATH}
                        rm -f thingsboard-*.rpm
                        rm -f application/target/thingsboard.rpm 2>/dev/null || true
                    """
                }
            }
        }
        
        stage('Download RPM') {
            when {
                expression { env.UPGRADE_REQUIRED == "true" }
            }
            steps {
                script {
                    echo "📥 Downloading ThingsBoard ${env.TARGET_VERSION} RPM..."
                    
                    sh """
                        cd ${TB_DOCKER_PATH}
                        
                        # Construct download URL
                        RPM_URL="${PACKAGE_REPO}/v${env.TARGET_VERSION}/thingsboard-${env.TARGET_VERSION}.rpm"
                        echo "📥 Downloading from: \$RPM_URL"
                        
                        # Download with retries
                        for i in {1..3}; do
                            if wget -q --timeout=120 --tries=1 "\$RPM_URL" -O "thingsboard-${env.TARGET_VERSION}.rpm"; then
                                echo "✅ Download successful on attempt \$i"
                                break
                            else
                                echo "❌ Download failed on attempt \$i"
                                sleep 10
                                if [ \$i -eq 3 ]; then
                                    exit 1
                                fi
                            fi
                        done
                        
                        # Verify download
                        if [ ! -f "thingsboard-${env.TARGET_VERSION}.rpm" ]; then
                            echo "❌ RPM file not found after download"
                            exit 1
                        fi
                        
                        # Check file size (should be > 100MB)
                        file_size=\$(stat -c%s "thingsboard-${env.TARGET_VERSION}.rpm")
                        if [ \$file_size -lt 104857600 ]; then
                            echo "❌ Downloaded file too small: \${file_size} bytes"
                            exit 1
                        fi
                        
                        echo "✅ Downloaded RPM: \$((\$file_size / 1024 / 1024)) MB"
                        
                        # Prepare for Docker build
                        mkdir -p application/target
                        cp "thingsboard-${env.TARGET_VERSION}.rpm" application/target/thingsboard.rpm
                        cp "thingsboard-${env.TARGET_VERSION}.rpm" thingsboard.rpm
                        
                        echo "✅ RPM ready for Docker build"
                    """
                }
            }
        }
        
        stage('Manual Approval') {
            when {
                allOf {
                    expression { env.UPGRADE_REQUIRED == "true" }
                    not { params.AUTO_PROCEED }
                    anyOf {
                        equals expected: 'staging', actual: params.ENVIRONMENT
                        equals expected: 'production', actual: params.ENVIRONMENT
                    }
                }
            }
            steps {
                script {
                    def deploymentInfo = """
                    🚀 Ready to upgrade ThingsBoard
                    
                    Environment: ${params.ENVIRONMENT}
                    Current Version: ${env.CURRENT_VERSION}
                    Target Version: ${env.TARGET_VERSION}
                    Container: ${env.CONTAINER_NAME}
                    Backup: ${env.BACKUP_DIR ?: 'No backup created'}
                    
                    The upgrade process will:
                    1. Stop current ThingsBoard container
                    2. Build new Docker image with v${env.TARGET_VERSION}
                    3. Run database upgrade (if needed)
                    4. Start new container
                    5. Verify health
                    
                    ⚠️ This will cause downtime during the upgrade process.
                    
                    Proceed with upgrade?
                    """
                    
                    input message: deploymentInfo, ok: 'Proceed with Upgrade', submitterParameter: 'APPROVER'
                    echo "✅ Upgrade approved by: ${env.APPROVER}"
                }
            }
        }
        
        // stage('Stop Current Container') {
        //     when {
        //         expression { env.UPGRADE_REQUIRED == "true" }
        //     }
        //     steps {
        //         script {
        //             echo "🛑 Stopping current ThingsBoard container..."
        //             sh """
        //                 cd ${TB_DOCKER_PATH}
                        
        //                 # Stop using docker-compose if available
        //                 if [ -f "${SERVER_COMPOSE}" ]; then
        //                     echo "Stopping via docker-compose..."
        //                     docker compose -f ${SERVER_COMPOSE} down || true
        //                 fi
                        
        //                 # Stop individual containers
        //                 docker stop ${env.CONTAINER_NAME} || true
        //                 docker rm -f ${env.CONTAINER_NAME} || true
                        
        //                 # Additional cleanup
        //                 docker stop thingsboard-testing-server || true
        //                 docker rm -f thingsboard-testing-server || true
                        
        //                 # Clean up
        //                 docker container prune -f
        //                 docker network prune -f
                        
        //                 echo "✅ Containers stopped and cleaned"
        //             """
        //         }
        //     }
        // }
        
        // stage('Run Database Upgrade') {
        //     when {
        //         expression { env.UPGRADE_REQUIRED == "true" }
        //     }
        //     steps {
        //         script {
        //             echo "🔄 Running database upgrade..."
        //             sh """
        //                 cd ${TB_DOCKER_PATH}
                        
        //                 # Build upgrade container if upgrade compose file exists
        //                 if [ -f "${UPGRADE_COMPOSE}" ]; then
        //                     echo "🔧 Building upgrade container..."
        //                     docker compose -f ${UPGRADE_COMPOSE} build --no-cache
                            
        //                     echo "🚀 Running database upgrade..."
        //                     docker compose -f ${UPGRADE_COMPOSE} up --abort-on-container-exit
                            
        //                     echo "🧹 Cleaning up upgrade container..."
        //                     docker compose -f ${UPGRADE_COMPOSE} down
        //                 else
        //                     echo "⚠️ No upgrade compose file found - database upgrade will be handled by main container"
        //                 fi
                        
        //                 echo "✅ Database upgrade completed"
        //             """
        //         }
        //     }
        // }
        
        // stage('Build New Container') {
        //     when {
        //         expression { env.UPGRADE_REQUIRED == "true" }
        //     }
        //     steps {
        //         script {
        //             echo "🏗️ Building ThingsBoard ${env.TARGET_VERSION} container..."
        //             sh """
        //                 cd ${TB_DOCKER_PATH}
                        
        //                 # Update docker-compose.yml with new version
        //                 if [ -f "${SERVER_COMPOSE}" ]; then
        //                     # Update image tag
        //                     sed -i "s|image: thingsboard:.*|image: thingsboard:${env.TARGET_VERSION}|g" ${SERVER_COMPOSE}
        //                     # Update container name
        //                     sed -i "s|container_name: thingsboard-.*|container_name: thingsboard-${env.TARGET_VERSION}|g" ${SERVER_COMPOSE}
                            
        //                     echo "✅ Updated ${SERVER_COMPOSE}:"
        //                     grep -E "(image:|container_name:)" ${SERVER_COMPOSE} | head -4
        //                 fi
                        
        //                 # Build the new image
        //                 docker build -t "thingsboard:${env.TARGET_VERSION}" . --no-cache
                        
        //                 # Verify image was created
        //                 docker images | grep "thingsboard.*${env.TARGET_VERSION}"
                        
        //                 echo "✅ Docker image built successfully"
        //             """
        //         }
        //     }
        // }
        
        // stage('Start New Container') {
        //     when {
        //         expression { env.UPGRADE_REQUIRED == "true" }
        //     }
        //     steps {
        //         script {
        //             echo "🚀 Starting ThingsBoard ${env.TARGET_VERSION}..."
        //             sh """
        //                 cd ${TB_DOCKER_PATH}
                        
        //                 # Start new container
        //                 docker compose -f ${SERVER_COMPOSE} up -d --remove-orphans
                        
        //                 echo "✅ Container started"
                        
        //                 # Show container status
        //                 sleep 5
        //                 docker compose -f ${SERVER_COMPOSE} ps
        //             """
                    
        //             env.NEW_CONTAINER_NAME = "thingsboard-${env.TARGET_VERSION}"
        //         }
        //     }
        // }
       

        
        // stage('Final Cleanup') {
        //     when {
        //         expression { env.UPGRADE_REQUIRED == "true" }
        //     }
        //     steps {
        //         script {
        //             echo "🧹 Final cleanup..."
        //             sh """
        //                 cd ${TB_DOCKER_PATH}
                        
        //                 # Remove downloaded RPMs
        //                 rm -f "thingsboard-${env.TARGET_VERSION}.rpm"
        //                 rm -f thingsboard.rpm
        //                 rm -f application/target/thingsboard.rpm
                        
        //                 # Clean up old Docker images (keep last 3 versions)
        //                 echo "🧹 Cleaning up old Docker images..."
        //                 docker images --format "table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}" | grep "^thingsboard:" | grep -v "${env.TARGET_VERSION}" | tail -n +4 | awk '{print \$2}' | xargs -r docker rmi || true
                        
        //                 echo "✅ Cleanup completed"
        //             """
        //         }
        //     }
        // }
    }
    
    post {
        success {
            script {
                if (env.UPGRADE_REQUIRED == "true") {
                    echo """
                    🎉 ThingsBoard upgrade completed successfully!
                    
                    ✅ Environment: ${params.ENVIRONMENT}
                    ✅ Upgraded: ${env.CURRENT_VERSION} → ${env.TARGET_VERSION}
                    ✅ Container: ${env.NEW_CONTAINER_NAME}
                    ✅ Web Interface: http://localhost:8080
                    ${env.BACKUP_DIR ? "✅ Backup: ${env.BACKUP_DIR}" : ""}
                    
                    🚀 ThingsBoard ${env.TARGET_VERSION} is now running and healthy!
                    """
                } else {
                    echo """
                    ✅ ThingsBoard is already up to date!
                    
                    Current Version: ${env.CURRENT_VERSION}
                    No upgrade was needed.
                    """
                }
                
                // Uncomment for email notifications
                // emailext (
                //     subject: "✅ ThingsBoard Upgrade Success - ${env.TARGET_VERSION}",
                //     body: "ThingsBoard successfully upgraded to ${env.TARGET_VERSION} in ${params.ENVIRONMENT}",
                //     to: "your-team@company.com"
                // )
            }
        }
        
        failure {
            script {
                echo """
                ❌ ThingsBoard upgrade failed!
                
                // Environment: ${params.ENVIRONMENT}
                // Current Version: ${env.CURRENT_VERSION}
                // Target Version: ${env.TARGET_VERSION}
                // ${env.BACKUP_DIR ? "Backup Location: ${env.BACKUP_DIR}" : ""}
                
                // Please check the logs above for details.
                // ${env.BACKUP_DIR ? "You can restore from the backup if needed." : ""}
                // """
                
                // Show container status for debugging
                // sh """
                //     cd ${TB_DOCKER_PATH}
                //     echo "📊 Current container status:"
                //     docker ps -a | grep thingsboard || echo "No ThingsBoard containers found"
                    
                //     if [ -n "${env.NEW_CONTAINER_NAME}" ] && docker ps -a | grep -q "${env.NEW_CONTAINER_NAME}"; then
                //         echo "📋 Failed container logs (last 50 lines):"
                //         docker logs "${env.NEW_CONTAINER_NAME}" | tail -50
                //     fi
                // """ ?: true
                
                // Uncomment for email notifications
                // emailext (
                //     subject: "❌ ThingsBoard Upgrade Failed - ${env.TARGET_VERSION}",
                //     body: "ThingsBoard upgrade to ${env.TARGET_VERSION} failed in ${params.ENVIRONMENT}. Check Jenkins logs.",
                //     to: "your-team@company.com"
                // )
            }
        }
        
        always {
            script {
                echo "📊 Final Status Summary:"
                sh """
                    cd ${TB_DOCKER_PATH}
                    
                    echo "=== Container Status ==="
                    docker ps | grep thingsboard || echo "No running ThingsBoard containers"
                    
                    echo ""
                    echo "=== Images ==="
                    docker images | grep thingsboard | head -5
                    
                    echo ""
                    echo "=== Disk Usage ==="
                    df -h . || true
                """ ?: true
            }
        }
    }
}
