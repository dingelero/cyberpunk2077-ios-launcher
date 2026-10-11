"""Version-locked native mobile display-loop correction; no gameplay removal."""
import struct
from game_streaming_patch import apply as streaming, UUID, offset
from macho import inspect, text_hash

VERSION = 'mobile-native30-v2'
BASE_TEXT = '271b77fc4c2f60e1d15897f3a4b494f8725fca98bd731f9162c4beed0edc4bdf'
FAILED_STREAMING_TEXT = '4261c095d35631e15be75777a08ca0045d87ea3ceac1f6dcd1e3436ae6b73bd8'
TEXT_SHA256 = 'ed2da0c2f4c0cd0078976b281747cd91ea31116d7cd87df5085642ba5a7d5d31'
ADDRESS, OLD, NEW = 0x101076200, 0x1e220000, 0x1e27d000

def apply(data):
    if inspect(data)['uuid'] != UUID:
        raise ValueError('Unsupported guest UUID')
    before = text_hash(data)
    if before not in (BASE_TEXT, FAILED_STREAMING_TEXT, TEXT_SHA256):
        raise ValueError('Unknown guest instruction hash; mobile patch refused')
    rollback = None
    if before == FAILED_STREAMING_TEXT:
        data, rollback = streaming(data, reverse=True)
    result = bytearray(data)
    at = offset(result, ADDRESS)
    expected = NEW if before == TEXT_SHA256 else OLD
    if struct.unpack_from('<I', result, at)[0] != expected:
        raise ValueError('Display-loop instruction mismatch')
    # updateVsyncLevel's VSync-off branch previously copied the native panel
    # refresh into all three CAFrameRateRange fields (120 Hz on this phone).
    # Request 30 Hz from the real CAMetalDisplayLink instead. The original
    # callback, drawable/semaphore, VSync-on branch and game update stay intact.
    struct.pack_into('<I', result, at, NEW)
    if text_hash(result) != TEXT_SHA256:
        raise ValueError('Patched executable hash mismatch')
    return bytes(result), {
        'version': VERSION, 'uuid': UUID, 'beforeTextSHA256': before,
        'afterTextSHA256': TEXT_SHA256, 'retiredStreamingPatchRollback': rollback,
        'instruction': {'virtualAddress': hex(ADDRESS), 'fileOffset': hex(at),
                        'before': hex(OLD), 'after': hex(NEW)},
        'displayLinkVSyncOffRequestedFPS': 30, 'vSyncOnBranchPreserved': True,
        'gameplayTickPhysicsAIUnchanged': True, 'gameplayContentRemoved': False,
        'streamingDefaults': {'StreamMaxLoadingThreads': 2,
            'FloodMinNonLoadingThreads': 2, 'DedicatedDecompressionMemoryBytes': 1048576},
        'nativeCallbackRateObserved': False, 'thermalImprovementVerified': False,
        'sustained30FPSFor30MinutesVerified': False,
    }
