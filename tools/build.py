"""Build a distributable from source and a SHA-256-verified official UE4SS ZIP."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import urllib.request
import zipfile

VERSION='0.2.1'
RUNTIME='UE4SS_v3.0.1-1176-g1ba38db4.zip'
RUNTIME_SHA256='e615ee7a2c24344ea5aeef85183d6cfd550f4f6352225976679f9fefffd0b9a5'
URL='https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental-latest/'+RUNTIME
EXE_SHA256='6c71ab55143add71e56c9477cdbfcb8f44e16d8d5c4df7c8c678396a6275cb4f'
ROOT=Path(__file__).resolve().parent.parent

def build(runtime_zip=None):
    archive=Path(runtime_zip) if runtime_zip else ROOT/'.cache'/RUNTIME
    if not archive.is_file():
        if runtime_zip:
            raise FileNotFoundError(archive)
        archive.parent.mkdir(parents=True,exist_ok=True)
        urllib.request.urlretrieve(URL,archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=RUNTIME_SHA256:
        raise ValueError('Official runtime ZIP SHA-256 does not match the pinned version')
    name=f'TS2-ShoulderCamera-v{VERSION}'
    out=ROOT/'dist'/name
    out.mkdir(parents=True,exist_ok=True)
    # Read only explicitly allowed files; never extract arbitrary archive paths.
    with zipfile.ZipFile(archive) as z:
        for member in ['dwmapi.dll','ue4ss/UE4SS.dll','ue4ss/LICENSE','ue4ss/UE4SS-settings.ini',
                       'ue4ss/Mods/shared/UEHelpers/UEHelpers.lua']:
            dest=out/'Win64'/member
            dest.parent.mkdir(parents=True,exist_ok=True)
            dest.write_bytes(z.read(member))
    mod=out/'Win64/ue4ss/Mods/TormentedShoulderCamera/Scripts'
    mod.mkdir(parents=True,exist_ok=True)
    for script in (ROOT/'src/TormentedShoulderCamera/Scripts').glob('*.lua'):
        shutil.copy2(script,mod/script.name)
    (out/'Win64/ue4ss/Mods/mods.txt').write_text('TormentedShoulderCamera : 1\n',encoding='ascii')
    for source in (ROOT/'installer').iterdir():
        if source.is_file(): shutil.copy2(source,out/source.name)
    for source in ['README.md','LICENSE','CHANGELOG.md']:
        shutil.copy2(ROOT/source,out/source)
    manifest={'mod':'TormentedShoulderCamera','version':VERSION,'engine':'5.5.4',
              'game_exe_sha256':EXE_SHA256,'ue4ss':'3.0.1-1176-g1ba38db4',
              'runtime_archive_sha256':RUNTIME_SHA256,'files':{}}
    for file in sorted((out/'Win64').rglob('*')):
        if file.is_file():
            manifest['files'][file.relative_to(out).as_posix()]=hashlib.sha256(file.read_bytes()).hexdigest()
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    result=ROOT/'dist'/(name+'.zip')
    with zipfile.ZipFile(result,'w',zipfile.ZIP_DEFLATED) as z:
        for file in sorted(out.rglob('*')):
            if file.is_file(): z.write(file,name+'/'+file.relative_to(out).as_posix())
    checksum=hashlib.sha256(result.read_bytes()).hexdigest()
    result.with_suffix('.zip.sha256').write_text(checksum+'  '+result.name+'\n',encoding='ascii')
    print(result)
    return out

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--runtime-zip',type=Path)
    build(parser.parse_args().runtime_zip)
