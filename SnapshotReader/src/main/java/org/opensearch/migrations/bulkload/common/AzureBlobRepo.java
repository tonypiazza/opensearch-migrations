package org.opensearch.migrations.bulkload.common;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobServiceClientBuilder;
import com.azure.storage.blob.models.BlobHierarchyItem;
import com.azure.storage.blob.models.ListBlobsOptions;
import com.azure.identity.DefaultAzureCredentialBuilder;
import lombok.Getter;
import lombok.extern.slf4j.Slf4j;

@Slf4j
public class AzureBlobRepo implements SourceRepo {
    private static final String INDICES_PREFIX_STR = "indices/";
    private final Path localDir;
    private final BlobContainerClient containerClient;
    private final SnapshotFileFinder fileFinder;
    private final String region;

    @Getter
    private final AzureBlobUri azureRepoUri;

    @Override
    public String toString() {
        return String.format("AzureBlobRepo [uri=%s, region=%s]", azureRepoUri.uri, region);
    }

    protected void ensureLocalDirectoryExists(Path localPath) {
        try {
            if (localPath != null) {
                Files.createDirectories(localPath);
            }
        } catch (IOException e) {
            throw new CantCreateLocalDir(localPath, e);
        }
    }

    protected boolean doesFileExistLocally(Path localPath) {
        return Files.exists(localPath);
    }

    private void ensureFileExistsLocally(AzureBlobUri azureUri, Path localPath) {
        ensureLocalDirectoryExists(localPath.getParent());

        if (doesFileExistLocally(localPath)) {
            log.atDebug().setMessage("File already exists locally: {}").addArgument(localPath).log();
            return;
        }

        log.atInfo()
            .setMessage("Downloading file from Azure: {} to {}").addArgument(azureUri.uri).addArgument(localPath).log();

        BlobClient blobClient = containerClient.getBlobClient(azureUri.key);
        blobClient.downloadToFile(localPath.toString());
    }

    public static AzureBlobRepo create(Path localDir, AzureBlobUri azureUri, String region, SnapshotFileFinder finder) {
        return create(localDir, azureUri, region, null, finder);
    }

    public static AzureBlobRepo create(Path localDir, AzureBlobUri azureUri, String region, String connectionString, SnapshotFileFinder finder) {
        BlobContainerClient containerClient;
        if (connectionString != null) {
            containerClient = new BlobServiceClientBuilder()
                .connectionString(connectionString)
                .buildClient()
                .getBlobContainerClient(azureUri.containerName);
        } else {
            var credential = new DefaultAzureCredentialBuilder().build();
            containerClient = new BlobServiceClientBuilder()
                .credential(credential)
                .buildClient()
                .getBlobContainerClient(azureUri.containerName);
        }
        return new AzureBlobRepo(localDir, azureUri, region, containerClient, finder);
    }

    protected AzureBlobRepo(Path localDir, AzureBlobUri azureUri, String region, BlobContainerClient containerClient, SnapshotFileFinder fileFinder) {
        this.localDir = localDir;
        this.azureRepoUri = azureUri;
        this.region = region;
        this.containerClient = containerClient;
        this.fileFinder = fileFinder;
    }

    @Override
    public Path getRepoRootDir() {
        return localDir;
    }

    @Override
    public Path getSnapshotRepoDataFilePath() {
        List<String> filesInRoot = listFilesInRoot();
        try {
            Path repoDataPath = fileFinder.getSnapshotRepoDataFilePath(localDir, filesInRoot);
            return fetch(repoDataPath);
        } catch (BaseSnapshotFileFinder.CannotFindRepoIndexFile e) {
            throw new CannotFindSnapshotRepoRoot(azureRepoUri.containerName, azureRepoUri.key);
        }
    }

    @Override
    public Path getGlobalMetadataFilePath(String snapshotId) {
        return fetch(fileFinder.getGlobalMetadataFilePath(localDir, snapshotId));
    }

    @Override
    public Path getSnapshotMetadataFilePath(String snapshotId) {
        return fetch(fileFinder.getSnapshotMetadataFilePath(localDir, snapshotId));
    }

    @Override
    public Path getIndexMetadataFilePath(String indexId, String indexFileId) {
        return fetch(fileFinder.getIndexMetadataFilePath(localDir, indexId, indexFileId));
    }

    @Override
    public Path getShardDirPath(String indexId, int shardId) {
        return fileFinder.getShardDirPath(localDir, indexId, shardId);
    }

    @Override
    public Path getShardMetadataFilePath(String snapshotId, String indexId, int shardId) {
        return fetch(fileFinder.getShardMetadataFilePath(localDir, snapshotId, indexId, shardId));
    }

    @Override
    public Path getBlobFilePath(String indexId, int shardId, String blobName) {
        return fetch(fileFinder.getBlobFilePath(localDir, indexId, shardId, blobName));
    }

    public static class CannotFindSnapshotRepoRoot extends RfsException {
        public CannotFindSnapshotRepoRoot(String container, String prefix) {
            super("Cannot find the snapshot repository root in Azure container: " + container + ", prefix: " + prefix);
        }
    }

    public static class CantCreateLocalDir extends RfsException {
        public CantCreateLocalDir(Path localPath, Throwable cause) {
            super("Failed to create the Azure local download directory: " + localPath, cause);
        }
    }

    private Path fetch(Path path) {
        ensureFileExistsLocally(makeAzureUri(path), path);
        return path;
    }

    protected AzureBlobUri makeAzureUri(Path filePath) {
        Path absLocalDir = localDir.toAbsolutePath().normalize();
        Path absFilePath = filePath.toAbsolutePath().normalize();

        String localDirStr = absLocalDir.toString();
        String filePathStr = absFilePath.toString();

        if (!filePathStr.startsWith(localDirStr)) {
            throw new IllegalArgumentException("File path must be under localDir: " + filePath);
        }

        String relativePathStr = filePathStr.substring(localDirStr.length());
        if (relativePathStr.startsWith(File.separator)) {
            relativePathStr = relativePathStr.substring(1);
        }

        relativePathStr = relativePathStr.replace('\\', '/');

        String baseUri = azureRepoUri.uri.endsWith("/")
            ? azureRepoUri.uri.substring(0, azureRepoUri.uri.length() - 1)
            : azureRepoUri.uri;

        String fullUri = relativePathStr.isEmpty()
            ? baseUri
            : baseUri + "/" + relativePathStr;

        return new AzureBlobUri(fullUri);
    }

    protected List<String> listFilesInRoot() {
        String prefixKey = azureRepoUri.key;
        if (prefixKey.endsWith("/")) {
            prefixKey = prefixKey.substring(0, prefixKey.length() - 1);
        }

        String listPrefix = prefixKey.isEmpty() ? null : prefixKey + "/";

        ListBlobsOptions options = new ListBlobsOptions();
        if (listPrefix != null) {
            options.setPrefix(listPrefix);
        }

        List<String> strippedKeys = new ArrayList<>();
        try {
            for (BlobHierarchyItem item : containerClient.listBlobsByHierarchy("/", options, null)) {
                if (item.isBlob()) {
                    String name = item.getName();
                    String stripped = name.substring(listPrefix == null ? 0 : listPrefix.length());
                    if (stripped.startsWith("/")) {
                        stripped = stripped.substring(1);
                    }
                    if (!stripped.isEmpty() && !stripped.contains("/")) {
                        strippedKeys.add(stripped);
                    }
                }
            }
        } catch (Exception e) {
            throw new CannotListObjects(azureRepoUri.containerName, prefixKey, e);
        }

        if (strippedKeys.isEmpty()) {
            throw new CannotFindSnapshotRepoRoot(azureRepoUri.containerName, prefixKey);
        }

        log.atDebug()
            .setMessage("From AzureBlobRepo: top-level files under {} -> {}")
            .addArgument(azureRepoUri)
            .addArgument(strippedKeys)
            .log();

        return strippedKeys;
    }

    public static class CannotListObjects extends RfsException {
        public CannotListObjects(String container, String prefix, Throwable cause) {
            super("Failed to list objects in Azure container: " + container + ", prefix: " + prefix, cause);
        }
    }

    public List<String> listTopLevelDirectories() {
        return listSubDirectories("");
    }

    public List<String> listSubDirectories(String relativePrefix) {
        String prefixKey = azureRepoUri.key;
        if (!prefixKey.isEmpty() && !prefixKey.endsWith("/")) {
            prefixKey = prefixKey + "/";
        }
        String fullPrefix = prefixKey + relativePrefix;
        if (!fullPrefix.isEmpty() && !fullPrefix.endsWith("/")) {
            fullPrefix = fullPrefix + "/";
        }

        ListBlobsOptions options = new ListBlobsOptions();
        options.setPrefix(fullPrefix);

        Set<String> dirs = new LinkedHashSet<>();
        try {
            for (BlobHierarchyItem item : containerClient.listBlobsByHierarchy("/", options, null)) {
                if (item.isPrefix()) {
                    String prefix = item.getName();
                    String dirName = prefix.substring(fullPrefix.length());
                    if (dirName.endsWith("/")) {
                        dirName = dirName.substring(0, dirName.length() - 1);
                    }
                    if (!dirName.isEmpty()) {
                        dirs.add(dirName);
                    }
                }
            }
        } catch (Exception e) {
            throw new CannotListObjects(azureRepoUri.containerName, fullPrefix, e);
        }

        return dirs.stream().sorted().toList();
    }

    public Path downloadAllFiles() {
        return downloadPrefix("");
    }

    public Path downloadFile(String relativePath) {
        var localPath = localDir.resolve(relativePath);
        return fetch(localPath);
    }

    public Path downloadPrefix(String prefix) {
        String baseKey = azureRepoUri.key;
        if (!baseKey.isEmpty() && !baseKey.endsWith("/")) {
            baseKey = baseKey + "/";
        }
        String fullPrefix = baseKey + prefix;
        if (!fullPrefix.isEmpty() && !fullPrefix.endsWith("/")) {
            fullPrefix = fullPrefix + "/";
        }

        ListBlobsOptions options = new ListBlobsOptions();
        options.setPrefix(fullPrefix);

        try {
            for (var blob : containerClient.listBlobs(options, null)) {
                String blobName = blob.getName();
                String relativePath = blobName.substring(baseKey.length());
                if (relativePath.isEmpty() || relativePath.endsWith("/")) continue;
                Path localPath = localDir.resolve(relativePath);
                ensureFileExistsLocally(new AzureBlobUri("az://" + azureRepoUri.containerName + "/" + blobName), localPath);
            }
        } catch (Exception e) {
            throw new CannotListObjects(azureRepoUri.containerName, fullPrefix, e);
        }

        log.atInfo().setMessage("Downloaded files from {} prefix '{}' to {}").addArgument(azureRepoUri).addArgument(prefix).addArgument(localDir).log();
        return localDir;
    }

    public static AzureBlobRepo createRaw(Path localDir, AzureBlobUri azureUri, String region) {
        return create(localDir, azureUri, region, null, null);
    }
}
