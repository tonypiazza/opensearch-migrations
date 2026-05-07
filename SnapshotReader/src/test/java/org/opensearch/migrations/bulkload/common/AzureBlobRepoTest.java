package org.opensearch.migrations.bulkload.common;

import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;

import org.opensearch.migrations.bulkload.common.AzureBlobRepo.CannotFindSnapshotRepoRoot;

import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.models.BlobHierarchyItem;
import com.azure.storage.blob.models.ListBlobsOptions;
import com.azure.storage.blob.models.BlobItem;
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
public class AzureBlobRepoTest {
    @Mock
    private BlobContainerClient mockContainerClient;
    @Mock
    private BlobClient mockBlobClient;
    @Mock
    private SnapshotFileFinder mockFileFinder;
    private TestableAzureBlobRepo testRepo;
    private Path testDir = Paths.get("/fake/path");
    private String testRegion = "us-fake-1";
    private AzureBlobUri testRepoUri = new AzureBlobUri("az://container-name/directory");
    private String testRepoFileName = "index-2";
    private AzureBlobUri testRepoFileUri = new AzureBlobUri(testRepoUri.uri + "/" + testRepoFileName);

    class TestableAzureBlobRepo extends AzureBlobRepo {
        public TestableAzureBlobRepo(Path localDir, AzureBlobUri azureRepoUri, String region, BlobContainerClient containerClient, SnapshotFileFinder fileFinder) {
            super(localDir, azureRepoUri, region, containerClient, fileFinder);
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
        protected AzureBlobUri makeAzureUri(Path filePath) {
            return super.makeAzureUri(filePath);
        }
    }

    @BeforeEach
    void setUp() {
        when(mockContainerClient.getBlobClient(anyString())).thenReturn(mockBlobClient);

        testRepo = Mockito.spy(new TestableAzureBlobRepo(testDir, testRepoUri, testRegion, mockContainerClient, mockFileFinder));
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

        String expectedKey = testRepo.makeAzureUri(expectedPath).key;

        verify(mockContainerClient).getBlobClient(expectedKey);
        verify(mockBlobClient).downloadToFile(expectedPath.toString());
    }

    @Test
    void GetSnapshotRepoDataFilePath_DoesNotExist() {
        BlobHierarchyItem mockEmptyItem = mock(BlobHierarchyItem.class);
        when(mockEmptyItem.isBlob()).thenReturn(false);
        when(mockEmptyItem.isPrefix()).thenReturn(false);

        @SuppressWarnings("unchecked")
        com.azure.core.http.rest.PagedIterable<BlobHierarchyItem> mockIterable =
            mock(com.azure.core.http.rest.PagedIterable.class);
        when(mockIterable.iterator()).thenReturn(List.of(mockEmptyItem).iterator());
        when(mockContainerClient.listBlobsByHierarchy(anyString(), any(ListBlobsOptions.class), any()))
                .thenReturn(mockIterable);

        CannotFindSnapshotRepoRoot thrown = assertThrows(
            CannotFindSnapshotRepoRoot.class,
            () -> testRepo.getSnapshotRepoDataFilePath()
        );

        assertThat(thrown.getMessage(), containsString(testRepoUri.containerName));
        assertThat(thrown.getMessage(), containsString(testRepoUri.key));
    }

    @Test
    void GetGlobalMetadataFilePath_AsExpected() {
        String snapshotId = "snapshot1";
        String metadataFileName = "meta-" + snapshotId + ".dat";
        Path expectedPath = testDir.resolve(metadataFileName);

        when(mockFileFinder.getGlobalMetadataFilePath(testDir, snapshotId)).thenReturn(expectedPath);
        doNothing().when(testRepo).ensureLocalDirectoryExists(expectedPath.getParent());

        Path filePath = testRepo.getGlobalMetadataFilePath(snapshotId);

        assertEquals(expectedPath, filePath);

        verify(testRepo, times(1)).ensureLocalDirectoryExists(expectedPath.getParent());

        String expectedKey = testRepo.makeAzureUri(expectedPath).key;

        verify(mockContainerClient).getBlobClient(expectedKey);
        verify(mockBlobClient).downloadToFile(expectedPath.toString());
    }

    @Test
    void GetSnapshotMetadataFilePath_AsExpected() {
        String snapshotId = "snapshot1";
        String snapshotFileName = "snap-" + snapshotId + ".dat";
        Path expectedPath = testDir.resolve(snapshotFileName);

        String expectedKey = testRepoUri.key + "/" + snapshotFileName;

        when(mockFileFinder.getGlobalMetadataFilePath(testDir, snapshotId)).thenReturn(expectedPath);
        doNothing().when(testRepo).ensureLocalDirectoryExists(expectedPath.getParent());

        Path filePath = testRepo.getGlobalMetadataFilePath(snapshotId);

        assertEquals(expectedPath, filePath);

        verify(testRepo, times(1)).ensureLocalDirectoryExists(expectedPath.getParent());

        verify(mockContainerClient).getBlobClient(expectedKey);
        verify(mockBlobClient).downloadToFile(expectedPath.toString());
    }

    @Test
    void GetIndexMetadataFilePath_AsExpected() {
        String indexId = "123abc";
        String indexFileId = "234bcd";
        String indexFileName = "indices/" + indexId + "/meta-" + indexFileId + ".dat";
        Path expectedPath = testDir.resolve(indexFileName);

        String expectedKey = testRepoUri.key + "/" + indexFileName;

        when(mockFileFinder.getIndexMetadataFilePath(testDir, indexId, indexFileId)).thenReturn(expectedPath);
        doNothing().when(testRepo).ensureLocalDirectoryExists(expectedPath.getParent());

        Path filePath = testRepo.getIndexMetadataFilePath(indexId, indexFileId);

        assertEquals(expectedPath, filePath);

        Mockito.verify(testRepo, times(1)).ensureLocalDirectoryExists(expectedPath.getParent());

        verify(mockContainerClient).getBlobClient(expectedKey);
        verify(mockBlobClient).downloadToFile(expectedPath.toString());
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

        String expectedKey = testRepoUri.key + "/" + shardFileName;

        when(mockFileFinder.getShardMetadataFilePath(testDir, snapshotId, indexId, shardId)).thenReturn(expectedPath);
        doNothing().when(testRepo).ensureLocalDirectoryExists(expectedPath.getParent());

        Path filePath = testRepo.getShardMetadataFilePath(snapshotId, indexId, shardId);

        assertEquals(expectedPath, filePath);
        Mockito.verify(testRepo, times(1)).ensureLocalDirectoryExists(expectedPath.getParent());

        verify(mockContainerClient).getBlobClient(expectedKey);
        verify(mockBlobClient).downloadToFile(expectedPath.toString());
    }

    @Test
    void GetBlobFilePath_AsExpected() {
        String blobName = "bobloblaw";
        String indexId = "123abc";
        int shardId = 7;
        String blobFileName = "indices/" + indexId + "/" + shardId + "/" + blobName;
        Path expectedPath = testDir.resolve(blobFileName);

        String expectedKey = testRepoUri.key + "/" + blobFileName;

        when(mockFileFinder.getBlobFilePath(testDir, indexId, shardId, blobName)).thenReturn(expectedPath);
        doNothing().when(testRepo).ensureLocalDirectoryExists(expectedPath.getParent());

        Path filePath = testRepo.getBlobFilePath(indexId, shardId, blobName);

        assertEquals(expectedPath, filePath);
        Mockito.verify(testRepo, times(1)).ensureLocalDirectoryExists(expectedPath.getParent());

        verify(mockContainerClient).getBlobClient(expectedKey);
        verify(mockBlobClient).downloadToFile(expectedPath.toString());
    }

    @Test
    void listFilesInRoot_ReturnsStrippedKeys() {
        BlobHierarchyItem mockItem1 = mock(BlobHierarchyItem.class);
        when(mockItem1.isBlob()).thenReturn(true);
        when(mockItem1.getName()).thenReturn("directory/file1.txt");

        BlobHierarchyItem mockItem2 = mock(BlobHierarchyItem.class);
        when(mockItem2.isBlob()).thenReturn(true);
        when(mockItem2.getName()).thenReturn("directory/file2.txt");

        BlobHierarchyItem mockItem3 = mock(BlobHierarchyItem.class);
        when(mockItem3.isBlob()).thenReturn(true);
        when(mockItem3.getName()).thenReturn("directory/foo/fooagain/file3.txt");

        @SuppressWarnings("unchecked")
        com.azure.core.http.rest.PagedIterable<BlobHierarchyItem> mockIterable =
            mock(com.azure.core.http.rest.PagedIterable.class);
        when(mockIterable.iterator()).thenReturn(List.of(mockItem1, mockItem2, mockItem3).iterator());
        when(mockContainerClient.listBlobsByHierarchy(anyString(), any(ListBlobsOptions.class), any()))
                .thenReturn(mockIterable);

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

        assertThat(thrown.getMessage(), containsString(testRepoUri.containerName));
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
        verify(mockContainerClient, never()).getBlobClient(anyString());
        verify(mockBlobClient, never()).downloadToFile(anyString());
    }
}
