package org.opensearch.migrations.replay.sink;

import java.io.IOException;
import java.io.OutputStream;
import java.io.UncheckedIOException;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.atomic.AtomicLong;
import java.util.zip.GZIPOutputStream;

import com.azure.storage.blob.BlobContainerClient;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;

@Slf4j
public class AzureBlobTupleSink implements TupleSink {
    private static final DateTimeFormatter TIMESTAMP_FORMAT =
        DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'").withZone(ZoneOffset.UTC);
    private static final DateTimeFormatter SHARD_FORMAT =
        DateTimeFormatter.ofPattern("yyyy/MM/dd/HH").withZone(ZoneOffset.UTC);

    private final ObjectMapper mapper = new ObjectMapper();
    private final BlobContainerClient containerClient;
    private final String container;
    private final String prefix;
    private final String replayerId;
    private final int sinkIndex;
    private final long rotateAfterBytes;
    private final Duration rotateAfterAge;
    private final int rotateAfterTuples;
    private final AtomicLong sequenceCounter = new AtomicLong();

    private OutputStream blobOutputStream;
    private GZIPOutputStream gzipOut;
    private String currentKey;
    private long uncompressedBytes;
    private int tupleCount;
    private Instant fileOpenedAt;
    private final List<CompletableFuture<Void>> pendingFutures = new ArrayList<>();

    public AzureBlobTupleSink(
        BlobContainerClient containerClient,
        String prefix,
        String replayerId,
        int sinkIndex,
        long rotateAfterBytes,
        Duration rotateAfterAge,
        int rotateAfterTuples
    ) {
        this.containerClient = containerClient;
        this.container = containerClient.getBlobContainerName();
        this.prefix = prefix;
        this.replayerId = replayerId;
        this.sinkIndex = sinkIndex;
        this.rotateAfterBytes = rotateAfterBytes;
        this.rotateAfterAge = rotateAfterAge;
        this.rotateAfterTuples = rotateAfterTuples;
        openNewStream();
    }

    @Override
    public void accept(Map<String, Object> tupleMap, CompletableFuture<Void> future) {
        try {
            byte[] json = mapper.writeValueAsBytes(tupleMap);
            gzipOut.write(json);
            gzipOut.write('\n');
            uncompressedBytes += json.length + 1;
            tupleCount++;
            pendingFutures.add(future);
        } catch (IOException e) {
            future.completeExceptionally(e);
            return;
        }
        if (shouldRotate()) {
            rotate();
        }
    }

    @Override
    public void flush() {
        if (pendingFutures.isEmpty()) {
            return;
        }
        rotate();
    }

    @Override
    public void periodicFlush() {
        if (!pendingFutures.isEmpty()) {
            rotate();
        }
    }

    @Override
    public void close() {
        if (gzipOut == null) {
            return;
        }
        if (!pendingFutures.isEmpty()) {
            rotate();
        } else {
            closeCurrentStream();
        }
        gzipOut = null;
        blobOutputStream = null;
    }

    private boolean shouldRotate() {
        return uncompressedBytes >= rotateAfterBytes
            || (rotateAfterTuples > 0 && tupleCount >= rotateAfterTuples)
            || Duration.between(fileOpenedAt, Instant.now()).compareTo(rotateAfterAge) >= 0;
    }

    private void rotate() {
        var key = currentKey;
        var futures = new ArrayList<>(pendingFutures);
        pendingFutures.clear();

        if (!closeCurrentStream()) {
            futures.forEach(f -> f.completeExceptionally(
                new IOException("Failed to finish gzip stream for azure://" + container + "/" + key)));
            openNewStream();
            return;
        }

        log.atInfo().setMessage("Completed Azure upload to azure://{}/{}").addArgument(container).addArgument(key).log();
        futures.forEach(f -> f.complete(null));

        openNewStream();
    }

    private boolean closeCurrentStream() {
        try {
            gzipOut.finish();
            blobOutputStream.close();
            return true;
        } catch (IOException e) {
            log.atError().setCause(e).setMessage("Failed to close Azure upload stream").log();
            return false;
        }
    }

    private String buildKey() {
        var now = Instant.now();
        var timestamp = TIMESTAMP_FORMAT.format(now);
        var shard = SHARD_FORMAT.format(now);
        var seq = sequenceCounter.getAndIncrement();
        var filename = String.format("tuples-%d-%s-%d.log.gz", sinkIndex, timestamp, seq);
        return prefix + replayerId + "/" + shard + "/" + filename;
    }

    private void openNewStream() {
        currentKey = buildKey();
        var blobClient = containerClient.getBlobClient(currentKey);
        var blockBlobClient = blobClient.getBlockBlobClient();
        blobOutputStream = blockBlobClient.getBlobOutputStream();
        try {
            gzipOut = new GZIPOutputStream(blobOutputStream, true);
        } catch (IOException e) {
            throw new UncheckedIOException("Failed to create gzip stream for Azure upload", e);
        }
        uncompressedBytes = 0;
        tupleCount = 0;
        fileOpenedAt = Instant.now();
    }
}
