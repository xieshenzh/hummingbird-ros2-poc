#!/usr/bin/env python3
"""Compare OCI layouts and report the small delta of a model-only release."""
import argparse, json, os, tarfile

def layers(path):
    with open(os.path.join(path, 'index.json')) as f: index=json.load(f)
    manifest=index['manifests'][0]['digest'].split(':',1)[1]
    with open(os.path.join(path, 'blobs', 'sha256', manifest)) as f: data=json.load(f)
    return data['layers']

def paths(layout, digest):
    p=os.path.join(layout,'blobs','sha256',digest.split(':',1)[1])
    try:
        with tarfile.open(p, 'r:*') as tf: return [m.name for m in tf.getmembers()]
    except tarfile.TarError: return []

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('old'); ap.add_argument('new')
    ap.add_argument('--max-changed',type=int,default=2); ap.add_argument('--report',required=True); a=ap.parse_args()
    old, new=layers(a.old), layers(a.new)
    oldd={x['digest'] for x in old}; changed=[x for x in new if x['digest'] not in oldd]
    report={'old_layers':len(old),'new_layers':len(new),'changed_layers':len(changed),
            'changed_bytes':sum(x.get('size',0) for x in changed),
            'changed_paths':[p for x in changed for p in paths(a.new,x['digest'])]}
    with open(a.report,'w') as f: json.dump(report,f,indent=2,sort_keys=True); f.write('\n')
    if len(changed)>a.max_changed: raise SystemExit('too many changed OCI layers: %d > %d' % (len(changed),a.max_changed))
if __name__=='__main__': main()
