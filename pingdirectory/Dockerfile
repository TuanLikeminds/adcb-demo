ARG BASE_IMAGE_ACR_REGISTRY_URL
ARG BASE_IMAGE_TAG
ARG BASE_IMAGE_REPOSITORY
# Use the specified base image with arguments
FROM ${BASE_IMAGE_ACR_REGISTRY_URL}/${BASE_IMAGE_REPOSITORY}:${BASE_IMAGE_TAG}

# Copy all files and directories from the local ./pingdirectory/ directory to /opt/in/ in the container
COPY serverProfile/. /opt/in/
