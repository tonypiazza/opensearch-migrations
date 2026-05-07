package org.opensearch.migrations.bulkload.common;

import java.util.List;

import org.opensearch.migrations.bulkload.tracing.IRfsContexts;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

public class AzureBlobSnapshotCreator extends SnapshotCreator {
    private static final ObjectMapper mapper = new ObjectMapper();

    private final String azureUri;
    private final String azureRegion;
    private final String azureEndpoint;
    private final Integer maxSnapshotRateMBPerNode;

    public AzureBlobSnapshotCreator(
        String snapshotName,
        String snapshotRepoName,
        OpenSearchClient client,
        String azureUri,
        String azureRegion,
        List<String> indexAllowlist,
        IRfsContexts.ICreateSnapshotContext context
    ) {
        this(snapshotName, snapshotRepoName, client, azureUri, azureRegion, null, indexAllowlist, null, context, false, true);
    }

    public AzureBlobSnapshotCreator(
        String snapshotName,
        String snapshotRepoName,
        OpenSearchClient client,
        String azureUri,
        String azureRegion,
        String azureEndpoint,
        List<String> indexAllowlist,
        Integer maxSnapshotRateMBPerNode,
        IRfsContexts.ICreateSnapshotContext context,
        boolean compressionEnabled,
        boolean includeGlobalState
    ) {
        super(snapshotName, snapshotRepoName, indexAllowlist, client, context, compressionEnabled, includeGlobalState);
        this.azureUri = azureUri;
        this.azureRegion = azureRegion;
        this.azureEndpoint = azureEndpoint;
        this.maxSnapshotRateMBPerNode = maxSnapshotRateMBPerNode;
    }

    @Override
    public ObjectNode getRequestBodyForRegisterRepo() {
        ObjectNode settings = mapper.createObjectNode();
        settings.put("container", getContainerName());
        settings.put("base_path", getBasePath());
        settings.put("compress", compressionEnabled);

        if (maxSnapshotRateMBPerNode != null) {
            settings.put("max_snapshot_bytes_per_sec", maxSnapshotRateMBPerNode + "mb");
        }

        ObjectNode body = mapper.createObjectNode();
        body.put("type", "azure");
        body.set("settings", settings);
        return body;
    }

    public String getContainerName() {
        return azureUri.split("/")[2];
    }

    public String getBasePath() {
        int thirdSlashIndex = azureUri.indexOf('/', 5);
        if (thirdSlashIndex == -1) {
            return null;
        }

        String rawBasePath = azureUri.substring(thirdSlashIndex + 1);
        if (rawBasePath.endsWith("/")) {
            return rawBasePath.substring(0, rawBasePath.length() - 1);
        } else {
            return rawBasePath;
        }
    }
}
