package org.opensearch.migrations.bulkload.common;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

import com.google.cloud.storage.Blob;
import com.google.cloud.storage.BlobId;
import com.google.cloud.storage.BlobListOption;
import com.google.cloud.storage.Storage;
import com.google.cloud.storage.StorageException;
import com.google.cloud.storage.StorageOptions;
import lombok.Getter;
import lombok.extern.slf4j.Slf4j;

@Slf4j
public class GcsRepo implements SourceRepo {
    private static final String INDICES_PREFIX_STR = "indices/";
    private final Path localDir;
    private final Storage storageClient;
    private final SnapshotFileFinder fileFinder;
    private final String region;

    @Getter
    private final GcsUri gcsRepoUri;

    @Override
    public String toString() {
        return String.format("GcsRepo [uri=%s, region=%s]", gcsRepoUri.uri, region);
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

    private void ensureFileExistsLocally(GcsUri gcsUri, Path localPath) {
        ensureLocalDirectoryExists(localPath.getParent());

        if (doesFileExistLocally(localPath)) {
            log.atDebug().setMessage("File already exists locally: {}").addArgument(localPath).log();
            return;
        }

        log.atInfo()
            .setMessage("Downloading file from GCS: {} to {}").addArgument(gcsUri.uri).addArgument(localPath).log();

        Blob blob = storageClient.get(BlobId.of(gcsUri.bucketName, gcsUri.key));
        if (blob == null) {
            throw new RuntimeException("Failed to get blob from GCS: " + gcsUri.uri);
        }
        blob.downloadTo(localPath);
    }

    public static GcsRepo create(Path localDir, GcsUri gcsUri, String region, SnapshotFileFinder finder) {
        Storage storage = StorageOptions.getDefaultInstance().getService();
        return new GcsRepo(localDir, gcsUri, region, storage, finder);
    }

    protected GcsRepo(Path localDir, GcsUri gcsUri, String region, Storage storageClient, SnapshotFileFinder fileFinder) {
        this.localDir = localDir;
        this.gcsRepoUri = gcsUri;
        this.region = region;
        this.storageClient = storageClient;
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
            throw new CannotFindSnapshotRepoRoot(gcsRepoUri.bucketName, gcsRepoUri.key);
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
        public CannotFindSnapshotRepoRoot(String bucket, String prefix) {
            super("Cannot find the snapshot repository root in GCS bucket: " + bucket + ", prefix: " + prefix);
        }
    }

    public static class CantCreateLocalDir extends RfsException {
        public CantCreateLocalDir(Path localPath, Throwable cause) {
            super("Failed to create the GCS local download directory: " + localPath, cause);
        }
    }

    private Path fetch(Path path) {
        ensureFileExistsLocally(makeGcsUri(path), path);
        return path;
    }

    protected GcsUri makeGcsUri(Path filePath) {
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

        String baseUri = gcsRepoUri.uri.endsWith("/")
            ? gcsRepoUri.uri.substring(0, gcsRepoUri.uri.length() - 1)
            : gcsRepoUri.uri;

        String fullUri = relativePathStr.isEmpty()
            ? baseUri
            : baseUri + "/" + relativePathStr;

        return new GcsUri(fullUri);
    }

    protected List<String> listFilesInRoot() {
        String prefixKey = gcsRepoUri.key;
        if (prefixKey.endsWith("/")) {
            prefixKey = prefixKey.substring(0, prefixKey.length() - 1);
        }

        String listPrefix = prefixKey.isEmpty() ? null : prefixKey + "/";

        var options = new ArrayList<BlobListOption>();
        options.add(BlobListOption.delimiter("/"));
        if (listPrefix != null) {
            options.add(BlobListOption.prefix(listPrefix));
        }

        com.google.cloud.Page<Blob> blobs;
        try {
            blobs = storageClient.list(
                gcsRepoUri.bucketName,
                options.toArray(new BlobListOption[0])
            );
        } catch (StorageException e) {
            throw new CannotListObjects(gcsRepoUri.bucketName, prefixKey, e);
        }

        List<String> strippedKeys = new ArrayList<>();
        for (Blob blob : blobs.iterateAll()) {
            String key = blob.getName();
            String stripped = key.substring(listPrefix == null ? 0 : listPrefix.length());
            if (stripped.startsWith("/")) {
                stripped = stripped.substring(1);
            }
            if (!stripped.isEmpty() && !stripped.contains("/")) {
                strippedKeys.add(stripped);
            }
        }

        if (strippedKeys.isEmpty()) {
            throw new CannotFindSnapshotRepoRoot(gcsRepoUri.bucketName, prefixKey);
        }

        log.atDebug()
            .setMessage("From GcsRepo: top-level files under {} -> {}")
            .addArgument(gcsRepoUri)
            .addArgument(strippedKeys)
            .log();

        return strippedKeys;
    }

    public static class CannotListObjects extends RfsException {
        public CannotListObjects(String bucket, String prefix, Throwable cause) {
            super("Failed to list objects in GCS bucket: " + bucket + ", prefix: " + prefix, cause);
        }
    }

    public List<String> listTopLevelDirectories() {
        return listSubDirectories("");
    }

    public List<String> listSubDirectories(String relativePrefix) {
        String prefixKey = gcsRepoUri.key;
        if (!prefixKey.isEmpty() && !prefixKey.endsWith("/")) {
            prefixKey = prefixKey + "/";
        }
        String fullPrefix = prefixKey + relativePrefix;
        if (!fullPrefix.isEmpty() && !fullPrefix.endsWith("/")) {
            fullPrefix = fullPrefix + "/";
        }

        var options = new ArrayList<BlobListOption>();
        options.add(BlobListOption.prefix(fullPrefix.isEmpty() ? null : fullPrefix));

        com.google.cloud.Page<Blob> blobs;
        try {
            blobs = storageClient.list(
                gcsRepoUri.bucketName,
                options.toArray(new BlobListOption[0])
            );
        } catch (StorageException e) {
            throw new CannotListObjects(gcsRepoUri.bucketName, fullPrefix, e);
        }

        Set<String> dirs = new LinkedHashSet<>();
        for (Blob blob : blobs.iterateAll()) {
            String name = blob.getName();
            if (name.length() > fullPrefix.length()) {
                String relative = name.substring(fullPrefix.length());
                int slashIndex = relative.indexOf('/');
                if (slashIndex >= 0) {
                    dirs.add(relative.substring(0, slashIndex));
                }
            }
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
        String baseKey = gcsRepoUri.key;
        if (!baseKey.isEmpty() && !baseKey.endsWith("/")) {
            baseKey = baseKey + "/";
        }
        String fullPrefix = baseKey + prefix;
        if (!fullPrefix.isEmpty() && !fullPrefix.endsWith("/")) {
            fullPrefix = fullPrefix + "/";
        }

        var options = new ArrayList<BlobListOption>();
        options.add(BlobListOption.prefix(fullPrefix.isEmpty() ? null : fullPrefix));

        com.google.cloud.Page<Blob> blobs;
        try {
            blobs = storageClient.list(
                gcsRepoUri.bucketName,
                options.toArray(new BlobListOption[0])
            );
        } catch (StorageException e) {
            throw new CannotListObjects(gcsRepoUri.bucketName, fullPrefix, e);
        }

        for (Blob blob : blobs.iterateAll()) {
            String relativePath = blob.getName().substring(baseKey.length());
            if (relativePath.isEmpty() || relativePath.endsWith("/")) continue;
            Path localPath = localDir.resolve(relativePath);
            ensureFileExistsLocally(new GcsUri("gs://" + gcsRepoUri.bucketName + "/" + blob.getName()), localPath);
        }

        log.atInfo().setMessage("Downloaded files from {} prefix '{}' to {}").addArgument(gcsRepoUri).addArgument(prefix).addArgument(localDir).log();
        return localDir;
    }

    public static GcsRepo createRaw(Path localDir, GcsUri gcsUri, String region) {
        Storage storage = StorageOptions.getDefaultInstance().getService();
        return new GcsRepo(localDir, gcsUri, region, storage, null);
    }
}
