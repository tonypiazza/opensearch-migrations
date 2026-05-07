package org.opensearch.migrations.replay.sink;

import java.io.IOException;
import java.io.OutputStream;
import java.io.UncheckedIOException;
import java.nio.channels.Channels;
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

import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.cloud.storage.BlobInfo;
import com.google.cloud.storage.Storage;
import lombok.extern.slf4j.Slf4j;

@Slf4j
public class GcsTupleSink implements TupleSink {
    private static final DateTimeFormatter TIMESTAMP_FORMAT =
        DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'").withZone(ZoneOffset.UTC);
    private static final DateTimeFormatter SHARD_FORMAT =
        DateTimeFormatter.ofPattern("yyyy/MM/dd/HH").withZone(ZoneOffset.UTC);

    private final ObjectMapper mapper = new ObjectMapper();
    private final Storage storage;
    private final String bucket;
    private final String prefix;
    private final String replayerId;
    private final int sinkIndex;
    private final long rotateAfterBytes;
    private final Duration rotateAfterAge;
    private final int rotateAfterTuples;
    private final AtomicLong sequenceCounter = new AtomicLong();

    private OutputStream gcsOutputStream;
    private GZIPOutputStream gzipOut;
    private String currentKey;
    private long uncompressedBytes;
    private int tupleCount;
    private Instant fileOpenedAt;
    private final List<CompletableFuture<Void>> pendingFutures = new ArrayList<>();

    public GcsTupleSink(
        Storage storage,
        String bucket,
        String prefix,
        String replayerId,
        int sinkIndex,
        long rotateAfterBytes,
        Duration rotateAfterAge,
        int rotateAfterTuples
    ) {
        this.storage = storage;
        this.bucket = bucket;
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
        gcsOutputStream = null;
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
                new IOException("Failed to finish gzip stream for gs://" + bucket + "/" + key)));
            openNewStream();
            return;
        }

        log.atInfo().setMessage("Completed GCS upload to gs://{}/{}").addArgument(bucket).addArgument(key).log();
        futures.forEach(f -> f.complete(null));

        openNewStream();
    }

    private boolean closeCurrentStream() {
        try {
            gzipOut.finish();
            gcsOutputStream.close();
            return true;
        } catch (IOException e) {
            log.atError().setCause(e).setMessage("Failed to close GCS upload stream").log();
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
        var blobInfo = BlobInfo.newBuilder(bucket, currentKey)
            .setContentType("application/gzip")
            .build();
        var writeChannel = storage.writer(blobInfo);
        gcsOutputStream = Channels.newOutputStream(writeChannel);
        try {
            gzipOut = new GZIPOutputStream(gcsOutputStream, true);
        } catch (IOException e) {
            throw new UncheckedIOException("Failed to create gzip stream for GCS upload", e);
        }
        uncompressedBytes = 0;
        tupleCount = 0;
        fileOpenedAt = Instant.now();
    }
}
