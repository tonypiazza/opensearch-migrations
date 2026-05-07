package org.opensearch.migrations.bulkload.common;

import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;

import org.opensearch.migrations.bulkload.common.GcsRepo.CannotFindSnapshotRepoRoot;

import com.google.cloud.Page;
import com.google.cloud.storage.Blob;
import com.google.cloud.storage.BlobId;
import com.google.cloud.storage.BlobListOption;
import com.google.cloud.storage.Storage;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.hamcrest.CoreMatchers.containsString;
import static org.hamcrest.MatcherAssert.assertThat;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
public class GcsRepoTest {
    @Mock
    private Storage mockStorage;
    @Mock
    private Blob mockBlob;
    @Mock
    private SnapshotFileFinder mockFileFinder;
    private TestableGcsRepo testRepo;
    private Path testDir = Paths.get("/fake/path");
    private String testRegion = "us-fake-1";
    private GcsUri testRepoUri = new GcsUri("gs://bucket-name/directory");
    private String testRepoFileName = "index-2";
    private GcsUri testRepoFileUri = new GcsUri(testRepoUri.uri + "/" + testRepoFileName);

    class TestableGcsRepo extends GcsRepo {
        public TestableGcsRepo(Path localDir, GcsUri gcsRepoUri, String region, Storage storageClient, SnapshotFileFinder fileFinder) {
            super(localDir, gcsRepoUri, region, storageClient, fileFinder);
        }

        @Override
        protected boolean doesFileExistLocally(Path path) {
            return false;
        }

        @Override
        protected List<String> listFilesInRoot() {
            return super.listFilesInRoot();
        }

        @Override
        protected GcsUri makeGcsUri(Path filePath) {
            return super.makeGcsUri(filePath);
        }
    }

    @BeforeEach
    void setUp() {
        when(mockStorage.get(any(BlobId.class))).thenReturn(mockBlob);
        when(mockBlob.downloadTo(any(Path.class))).thenReturn(mockBlob);

        testRepo = Mockito.spy(new TestableGcsRepo(testDir, testRepoUri, testRegion, mockStorage, mockFileFinder));
    }

    @Test
    void GetRepoRootDir_AsExpected() {
        Path filePath = testRepo.getRepoRootDir();

        assertEquals(testDir, filePath);
    }

    @Test
    void GetSnapshotRepoDataFilePath_AsExpected() {
        doReturn(List.of(testRepoFileName)).when(testRepo).listFilesInRoot();

        Path expectedPath = testDir.resolve(testRepoFileName);

        when(mockFileFinder.getSnapshotRepoDataFilePath(eq(testDir), anyList()))
                .thenReturn(expectedPath);

        doReturn(false).when(testRepo).doesFileExistLocally(expectedPath);

        doNothing().when(testRepo).ensureLocalDirectoryExists(expectedPath.getParent());

        Path filePath = testRepo.getSnapshotRepoDataFilePath();

        assertEquals(expectedPath, filePath);
        verify(testRepo).ensureLocalDirectoryExists(expectedPath.getParent());

        String expectedKey = testRepo.makeGcsUri(expectedPath).key;

        verify(mockStorage).get(eq(BlobId.of(testRepoUri.bucketName, expectedKey)));
        verify(mockBlob).downloadTo(expectedPath);
    }

    @Test
    void GetSnapshotRepoDataFilePath_DoesNotExist() {
        @SuppressWarnings("unchecked")
        Page<Blob> mockPage = mock(Page.class);
        when(mockStorage.list(anyString(), any(BlobListOption[].class)))
                .thenReturn(mockPage);
        when(mockPage.iterateAll()).thenReturn(List.of());

        CannotFindSnapshotRepoRoot thrown = assertThrows(
            CannotFindSnapshotRepoRoot.class,
            () -> testRepo.getSnapshotRepoDataFilePath()
        );

        assertThat(thrown.getMessage(), containsString(testRepoUri.bucketName));
        assertThat(thrown.getMessage(), containsString(testRepoUri.key));
    }

    @Test
    void GetGlobalMetadataFilePath_AsExpected() {
        String snapshotId = "snapshot1";
        String metadataFileName = "meta-" + snapshotId + ".dat";
        Path expectedPath = testDir.resolve(metadataFileName);
        String expectedBucketName = testRepoUri.bucketName;

        when(mockFileFinder.getGlobalMetadataFilePath(testDir, snapshotId)).thenReturn(expectedPath);
        doNothing().when(testRepo).ensureLocalDirectoryExists(expectedPath.getParent());

        Path filePath = testRepo.getGlobalMetadataFilePath(snapshotId);

        assertEquals(expectedPath, filePath);

        verify(testRepo, times(1)).ensureLocalDirectoryExists(expectedPath.getParent());

        String expectedKey = testRepo.makeGcsUri(expectedPath).key;

        verify(mockStorage).get(eq(BlobId.of(expectedBucketName, expectedKey)));
        verify(mockBlob).downloadTo(expectedPath);
    }

    @Test
    void GetSnapshotMetadataFilePath_AsExpected() {
        String snapshotId = "snapshot1";
        String snapshotFileName = "snap-" + snapshotId + ".dat";
        Path expectedPath = testDir.resolve(snapshotFileName);

        String expectedBucketName = testRepoUri.bucketName;
        String expectedKey = testRepoUri.key + "/" + snapshotFileName;

        when(mockFileFinder.getGlobalMetadataFilePath(testDir, snapshotId)).thenReturn(expectedPath);
        doNothing().when(testRepo).ensureLocalDirectoryExists(expectedPath.getParent());

        Path filePath = testRepo.getGlobalMetadataFilePath(snapshotId);

        assertEquals(expectedPath, filePath);

        verify(testRepo, times(1)).ensureLocalDirectoryExists(expectedPath.getParent());

        verify(mockStorage).get(eq(BlobId.of(expectedBucketName, expectedKey)));
        verify(mockBlob).downloadTo(expectedPath);
    }

    @Test
    void GetIndexMetadataFilePath_AsExpected() {
        String indexId = "123abc";
        String indexFileId = "234bcd";
        String indexFileName = "indices/" + indexId + "/meta-" + indexFileId + ".dat";
        Path expectedPath = testDir.resolve(indexFileName);

        String expectedBucketName = testRepoUri.bucketName;
        String expectedKey = testRepoUri.key + "/" + indexFileName;

        when(mockFileFinder.getIndexMetadataFilePath(testDir, indexId, indexFileId)).thenReturn(expectedPath);
        doNothing().when(testRepo).ensureLocalDirectoryExists(expectedPath.getParent());

        Path filePath = testRepo.getIndexMetadataFilePath(indexId, indexFileId);

        assertEquals(expectedPath, filePath);

        Mockito.verify(testRepo, times(1)).ensureLocalDirectoryExists(expectedPath.getParent());

        verify(mockStorage).get(eq(BlobId.of(expectedBucketName, expectedKey)));
        verify(mockBlob).downloadTo(expectedPath);
    }

    @Test
    void GetShardDirPath_AsExpected() {
        String indexId = "123abc";
        int shardId = 7;
        String shardDirName = "indices/" + indexId + "/" + shardId;
        Path expectedPath = testDir.resolve(shardDirName);

        when(mockFileFinder.getShardDirPath(testDir, indexId, shardId)).thenReturn(expectedPath);

        Path filePath = testRepo.getShardDirPath(indexId, shardId);

        assertEquals(expectedPath, filePath);
    }

    @Test
    void GetShardMetadataFilePath_AsExpected() {
        String snapshotId = "snapshot1";
        String indexId = "123abc";
        int shardId = 7;
        String shardFileName = "indices/" + indexId + "/" + shardId + "/snap-" + snapshotId + ".dat";
        Path expectedPath = testDir.resolve(shardFileName);

        String expectedBucketName = testRepoUri.bucketName;
        String expectedKey = testRepoUri.key + "/" + shardFileName;

        when(mockFileFinder.getShardMetadataFilePath(testDir, snapshotId, indexId, shardId)).thenReturn(expectedPath);
        doNothing().when(testRepo).ensureLocalDirectoryExists(expectedPath.getParent());

        Path filePath = testRepo.getShardMetadataFilePath(snapshotId, indexId, shardId);

        assertEquals(expectedPath, filePath);
        Mockito.verify(testRepo, times(1)).ensureLocalDirectoryExists(expectedPath.getParent());

        verify(mockStorage).get(eq(BlobId.of(expectedBucketName, expectedKey)));
        verify(mockBlob).downloadTo(expectedPath);
    }

    @Test
    void GetBlobFilePath_AsExpected() {
        String blobName = "bobloblaw";
        String indexId = "123abc";
        int shardId = 7;
        String blobFileName = "indices/" + indexId + "/" + shardId + "/" + blobName;
        Path expectedPath = testDir.resolve(blobFileName);

        String expectedBucketName = testRepoUri.bucketName;
        String expectedKey = testRepoUri.key + "/" + blobFileName;

        when(mockFileFinder.getBlobFilePath(testDir, indexId, shardId, blobName)).thenReturn(expectedPath);
        doNothing().when(testRepo).ensureLocalDirectoryExists(expectedPath.getParent());

        Path filePath = testRepo.getBlobFilePath(indexId, shardId, blobName);

        assertEquals(expectedPath, filePath);
        Mockito.verify(testRepo, times(1)).ensureLocalDirectoryExists(expectedPath.getParent());

        verify(mockStorage).get(eq(BlobId.of(expectedBucketName, expectedKey)));
        verify(mockBlob).downloadTo(expectedPath);
    }

    @Test
    void listFilesInRoot_ReturnsStrippedKeys() {
        @SuppressWarnings("unchecked")
        Page<Blob> mockPage = mock(Page.class);
        Blob mockBlob1 = mock(Blob.class);
        when(mockBlob1.getName()).thenReturn("directory/file1.txt");
        Blob mockBlob2 = mock(Blob.class);
        when(mockBlob2.getName()).thenReturn("directory/file2.txt");
        Blob mockBlob3 = mock(Blob.class);
        when(mockBlob3.getName()).thenReturn("directory/foo/fooagain/file3.txt");

        when(mockStorage.list(anyString(), any(BlobListOption[].class)))
                .thenReturn(mockPage);
        when(mockPage.iterateAll()).thenReturn(List.of(mockBlob1, mockBlob2, mockBlob3));

        List<String> files = testRepo.listFilesInRoot();

        assertEquals(List.of("file1.txt", "file2.txt"), files);
    }

    @Test
    void getSnapshotRepoDataFilePath_WithEmptyFileName() {
        doReturn(List.of()).when(testRepo).listFilesInRoot();

        when(mockFileFinder.getSnapshotRepoDataFilePath(eq(testDir), eq(List.of())))
                .thenThrow(new BaseSnapshotFileFinder.CannotFindRepoIndexFile("No matching index-N file found"));

        CannotFindSnapshotRepoRoot thrown = assertThrows(
                CannotFindSnapshotRepoRoot.class,
                () -> testRepo.getSnapshotRepoDataFilePath()
        );

        assertThat(thrown.getMessage(), containsString(testRepoUri.bucketName));
        assertThat(thrown.getMessage(), containsString(testRepoUri.key));
    }

    @Test
    void testFetchAlreadyExistsLocally() {
        String blobName = "existing-file.dat";
        String indexId = "123abc";
        int shardId = 7;
        String blobFileName = "indices/" + indexId + "/" + shardId + "/" + blobName;
        Path expectedPath = testDir.resolve(blobFileName);

        when(mockFileFinder.getBlobFilePath(testDir, indexId, shardId, blobName)).thenReturn(expectedPath);
        doNothing().when(testRepo).ensureLocalDirectoryExists(expectedPath.getParent());
        doReturn(true).when(testRepo).doesFileExistLocally(expectedPath);

        Path filePath = testRepo.getBlobFilePath(indexId, shardId, blobName);

        assertEquals(expectedPath, filePath);
        verify(mockStorage, never()).get(any(BlobId.class));
        verify(mockBlob, never()).downloadTo(any(Path.class));
    }
}
