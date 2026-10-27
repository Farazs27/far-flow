#!/usr/bin/env python3
"""Provision pinned public model artifacts; runtime inference never calls this script."""
import concurrent.futures, hashlib, json, pathlib, subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
DEST=pathlib.Path.home()/'Library/Application Support/FarFlow/Models'
def get_json(url):
    return json.loads(subprocess.check_output(['curl','--fail','--silent','--show-error','--location',url]))
def fetch(item):
    repo,rev,path,expected,folder=item
    dest=DEST/folder/path
    dest.parent.mkdir(parents=True,exist_ok=True)
    if not dest.exists() or (expected and hashlib.sha256(dest.read_bytes()).hexdigest()!=expected):
        temporary=dest.with_name(dest.name+'.download')
        subprocess.run(['curl','--fail','--silent','--show-error','--location','--retry','3',f'https://huggingface.co/{repo}/resolve/{rev}/{path}','-o',str(temporary)],check=True)
        digest=hashlib.sha256(temporary.read_bytes()).hexdigest()
        if expected and digest!=expected: raise RuntimeError('Checksum mismatch: '+path)
        temporary.replace(dest)
    digest=hashlib.sha256(dest.read_bytes()).hexdigest()
    return {'path':path,'sha256':digest,'bytes':dest.stat().st_size}
models=[('parakeet-v3','FluidInference/parakeet-tdt-0.6b-v3-coreml','7dd20fe6b1797d35f5e3307e8b1732d9a178edfe','CC-BY-4.0'),('qwen-cleanup','mlx-community/Qwen3-4B-Instruct-2507-4bit','50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b','Apache-2.0')]
manifest=[]
for folder,repo,revision,license_name in models:
    revision=revision or get_json('https://huggingface.co/api/models/'+repo)['sha']
    tree=get_json(f'https://huggingface.co/api/models/{repo}/tree/{revision}?recursive=true&expand=false')
    selected=[]
    for f in tree:
        p=f['path']
        if f['type']!='file': continue
        if folder=='parakeet-v3':
            if not (p.split('/')[0] in ['Preprocessor.mlmodelc','Encoder_v2.mlmodelc','Decoder.mlmodelc','JointDecisionv3.mlmodelc'] or p=='parakeet_vocab.json'):continue
        elif p not in ['README.md','config.json','generation_config.json','model.safetensors','model.safetensors.index.json','tokenizer.json','tokenizer_config.json','special_tokens_map.json','added_tokens.json','vocab.json','merges.txt','chat_template.jinja']:continue
        selected.append((repo,revision,p,f.get('lfs',{}).get('oid'),folder))
    print('Provisioning',repo,revision,flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool: files=list(pool.map(fetch,selected))
    record={'id':folder,'repository':repo,'revision':revision,'license':license_name,'files':files}
    (DEST/folder/'farflow-model.json').write_text(json.dumps(record,indent=2))
    manifest.append(record)
    print(folder,':',sum(f['bytes'] for f in files),'bytes verified',flush=True)
(ROOT/'FarFlow/Resources/ModelManifest.json').write_text(json.dumps(manifest,indent=2))
print('All models installed at',DEST,flush=True)
