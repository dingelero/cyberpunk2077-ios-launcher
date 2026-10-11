"""Version-locked native-30 candidate; effectiveness requires user gameplay QA."""
import argparse, hashlib, json, struct
from pathlib import Path
from common import config, output, write_json
from macho import inspect, text_hash
from mobile_engine_patch import apply as apply_mobile, VERSION as ENGINE_VERSION, TEXT_SHA256, FAILED_STREAMING_TEXT

VERSION = 'universal-v5'
NODE_BATCH = 192
PREFIX_TEXT_SHA256 = '271b77fc4c2f60e1d15897f3a4b494f8725fca98bd731f9162c4beed0edc4bdf'
OPTIONS_SHA256 = '5fec2d7298c73bca99451a1259c5a16d16ff24248d754d150ccb9e306a01ef1e'
RENDERING_SHA256 = '32fd1f5cdeb64325bc0e38c1a55a161e6dd8b551001f6f793ac1056986f968df'

def expected_text(metadata):
    profile = metadata.get('performanceProfile')
    if profile is None:
        return config()['memory_patch_text_sha256']
    if profile != VERSION:
        raise ValueError('Unknown performance instruction profile')
    return TEXT_SHA256

def patch(platform):
    path = output(platform)/'prepared/CyberpunkGuest.dylib'
    data = bytearray(path.read_bytes()); cfg = config(); info = inspect(data)
    if info['uuid'] != cfg['game_uuid']:
        raise ValueError('Unsupported game UUID')
    before = text_hash(data)
    if before not in (PREFIX_TEXT_SHA256, FAILED_STREAMING_TEXT, TEXT_SHA256):
        if before != cfg['memory_patch_text_sha256']:
            raise ValueError('Apply the four base capacity patches first')
        # Descriptor offset +0x10 is the initial committed prefix. The setup
        # at 0xa0b4 commits that prefix, while 0xa1c8 grows it on demand. Keep
        # the 8 GiB reserve, growth granularity, locks and failure paths intact.
        if struct.unpack_from('<I', data, 0xf704)[0] != 0x52a58008:
            raise ValueError('Initial-commit instruction does not match')
        struct.pack_into('<I', data, 0xf704, 0x52a10008) # 704 -> 128 MiB
        if text_hash(data) != PREFIX_TEXT_SHA256:
            raise ValueError('Unexpected candidate __text hash')
    data, engine_report = apply_mobile(data)
    path.write_bytes(data)
    write_json(output(platform)/'engine-mobile-patch.json',engine_report)
    metadata_path = output(platform)/'guest.json'
    metadata = json.loads(metadata_path.read_text())
    metadata['performanceProfile'] = VERSION
    metadata['guestTextSHA256'] = TEXT_SHA256
    metadata['enginePatch'] = ENGINE_VERSION
    write_json(metadata_path, metadata)
    write_json(output(platform)/'performance-patch.json', {
        'profile': VERSION, 'uuid': cfg['game_uuid'], 'beforeTextSHA256': before,
        'afterTextSHA256': TEXT_SHA256, 'additionalInstructionCount': 2,
        'enginePatch': ENGINE_VERSION, 'engineInstructionCount': 1,
        'offset': '0xf704', 'old': '0x52a58008', 'new': '0x52a10008',
        'initialCommittedPrefixMiB': {'before': 704, 'after': 128},
        'growthOnDemandPreserved': True, 'virtualReserveBytesUnchanged': True,
        'physicalMemorySavingsVerified': False, 'sustained30FPSVerified': False})
    print('Applied native mobile display-loop correction; retired streaming defaults. Runtime effect unverified.')

def stage_configuration(app):
    game = Path(config()['game_root'])
    rendering = (game/'engine/config/platform/mac/rendering.ini').read_bytes()
    options = (game/'r6/config/settings/platform/mac/options.json').read_bytes()
    if hashlib.sha256(rendering).hexdigest() != RENDERING_SHA256:
        raise ValueError('Unexpected source macOS rendering.ini')
    if hashlib.sha256(options).hexdigest() != OPTIONS_SHA256:
        raise ValueError('Unexpected source macOS options.json')
    schema = json.loads(options)
    scaling = next(o for g in schema['options'] for o in g['options'] if o['name']=='ResolutionScaling')
    # The 2.31 Mac schema keeps old machine enum names. Index 1 / FSR2
    # displays as native MetalFX; index 3 / MetalFX displays as FSR3.
    if scaling['values'][1] != 'FSR2' or scaling['display_values'][1] != 'UI-Settings-Video-Advanced-MFX':
        raise ValueError('Native MetalFX enum mapping changed')
    folder = app/'PerformanceProfile'; folder.mkdir(exist_ok=True)
    # Preserve the engine's native retention policy. Shortening lifetime without
    # streaming traces can increase decompression and resource re-upload churn.
    rendering += b'\r\n[Streaming]\r\nMaxNodesPerFrame=' + str(NODE_BATCH).encode() + b'\r\n'
    (folder/'rendering.ini').write_bytes(rendering)
    (folder/'options.json').write_bytes(options)
    write_json(folder/'profile.json', {
        'version': VERSION, 'requestedDRSMinimumPercent': 40, 'DRSMaximumPercent': 50,
        'nativeMetalFXMachineEnum': 'FSR2', 'nativeMetalFXIndex': 1,
        'resourceCacheExpiryOverride': None, 'graphicsQualityForced': False,
        'gameplayContentModified': False, 'targetDevice': 'iPhone and iPad; six selectable device presets',
        'enginePatch':ENGINE_VERSION, 'engineDefaultsChanged':False,
        'nodeAttachmentBudget':{'nativeDefault':300,'configured':NODE_BATCH,
            'whileLoadingDefaultPreserved':999999,'streamingDistancesPreserved':True,
            'category':'Streaming','parameter':'MaxNodesPerFrame',
            'nativeConsumer':'0x103371ddc','nativeCurrentValue':'0x1090d394c',
            'configurationApplicationVerified':False,'stutterReductionVerified':False},
        'independentFPSLimiterDefault':False,'HDDModeDefault':'Off',
        'ordinaryMainThreadPeriodicDiagnostics':False,
        'frameGenerationDefault':'Off', 'nativeDisplayLoopRequestFPS':30,
        'stutterReductionVerified':False,
        'originalOptionsSHA256': OPTIONS_SHA256, 'originalRenderingSHA256': RENDERING_SHA256,
        'profileRenderingSHA256':hashlib.sha256(rendering).hexdigest(),
        'runtimeQARequired': True, 'sustained30FPSVerified': False, 'outputHeightChoices':[720,1080],
        'devicePresetCount':6, 'interfaceLanguages':['zh','en'], 'internalRenderScaleDeviceAdaptive':True})

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['ios','iossim'], default='ios')
    patch(parser.parse_args().platform)
