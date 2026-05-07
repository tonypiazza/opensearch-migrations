package org.opensearch.migrations.bulkload.common;

import java.util.List;

import org.opensearch.migrations.bulkload.tracing.IRfsContexts;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

public class GcsSnapshotCreator extends SnapshotCreator {
    private static final ObjectMapper mapper = new ObjectMapper();

    private final String gcsUri;
    private final String gcsRegion;
    private final String gcsEndpoint;
    private final Integer maxSnapshotRateMBPerNode;

    public GcsSnapshotCreator(
        String snapshotName,
        String snapshotRepoName,
        OpenSearchClient client,
        String gcsUri,
        String gcsRegion,
        List<String> indexAllowlist,
        IRfsContexts.ICreateSnapshotContext context
    ) {
        this(snapshotName, snapshotRepoName, client, gcsUri, gcsRegion, null, indexAllowlist, null, context, false, true);
    }

    public GcsSnapshotCreator(
        String snapshotName,
        String snapshotRepoName,
        OpenSearchClient client,
        String gcsUri,
        String gcsRegion,
        String gcsEndpoint,
        List<String> indexAllowlist,
        Integer maxSnapshotRateMBPerNode,
        IRfsContexts.ICreateSnapshotContext context,
        boolean compressionEnabled,
        boolean includeGlobalState
    ) {
        super(snapshotName, snapshotRepoName, indexAllowlist, client, context, compressionEnabled, includeGlobalState);
        this.gcsUri = gcsUri;
        this.gcsRegion = gcsRegion;
        this.gcsEndpoint = gcsEndpoint;
        this.maxSnapshotRateMBPerNode = maxSnapshotRateMBPerNode;
    }

    @Override
    public ObjectNode getRequestBodyForRegisterRepo() {
        ObjectNode settings = mapper.createObjectNode();
        settings.put("bucket", getBucketName());
        settings.put("base_path", getBasePath());
        settings.put("compress", compressionEnabled);

        if (maxSnapshotRateMBPerNode != null) {
            settings.put("max_snapshot_bytes_per_sec", maxSnapshotRateMBPerNode + "mb");
        }

        ObjectNode body = mapper.createObjectNode();
        body.put("type", "gcs");
        body.set("settings", settings);
        return body;
    }

    public String getBucketName() {
        return gcsUri.split("/")[2];
    }

    public String getBasePath() {
        int thirdSlashIndex = gcsUri.indexOf('/', 5);
        if (thirdSlashIndex == -1) {
            return null;
        }

        String rawBasePath = gcsUri.substring(thirdSlashIndex + 1);
        if (rawBasePath.endsWith("/")) {
            return rawBasePath.substring(0, rawBasePath.length() - 1);
        } else {
            return rawBasePath;
        }
    }
}
