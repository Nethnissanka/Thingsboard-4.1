FROM rockylinux:9

#ARG TB_VERSION=4.1.0
#ENV TB_VERSION=${TB_VERSION}

# Install dependencies
RUN dnf install -y wget rpm java-17-openjdk net-tools && dnf clean all

# Copy the built RPM into the image
#COPY thingsboard-${TB_VERSION}.rpm thingsboard.rpm
COPY application/target/thingsboard.rpm /tmp/

# Install ThingsBoard
RUN rpm -ivh /tmp/thingsboard.rpm && rm -f /tmp/thingsboard.rpm
#RUN rpm -Uvh thingsboard.rpm && rm -f thingsboard.rpm

# Expose ThingsBoard UI/API port
EXPOSE 8080

# Start TB with default command
CMD ["java", "-jar", "/usr/share/thingsboard/bin/thingsboard.jar"]

# Run upgrade then start ThingsBoard
#CMD ["/bin/bash", "-c", "/usr/share/thingsboard/bin/install/upgrade.sh && java -jar /usr/share/thingsboard/bin/thingsboard.jar"]
