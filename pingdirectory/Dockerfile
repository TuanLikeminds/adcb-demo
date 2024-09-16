ARG BASE_IMAGE_ACR_REGISTRY_URL
ARG PRODUCT_NAME
ARG BASE_IMAGE_TAG

# Use the specified base image with arguments
FROM ${BASE_IMAGE_ACR_REGISTRY_URL}/${PRODUCT_NAME}:${BASE_IMAGE_TAG}

# Copy all files and directories from the local ./pingdirectory/ directory to /opt/in/ in the container
COPY serverProfile/. /opt/in/
