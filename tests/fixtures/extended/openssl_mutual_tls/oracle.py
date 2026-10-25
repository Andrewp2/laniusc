"""Finite native OpenSSL mTLS peers/oracles; no TLS or cryptographic engine."""
import importlib.util
import os
from pathlib import Path
import re
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
sys.dont_write_bytecode=True
from certificates import PASSPHRASE
BASE=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('mutual_client',BASE/'openssl_tls_server'/'client.py')
CLIENT=importlib.util.module_from_spec(spec);spec.loader.exec_module(CLIENT)
Client,Connection,binary=CLIENT.Client,CLIENT.Connection,CLIENT.binary
EXE=None;CERTS=None;CASES=0


def context(role, certificate, key, trust, version):
    if role==0:
        result=ssl.create_default_context(cafile=CERTS/f'{trust}.pem')
        if certificate: result.load_cert_chain(CERTS/certificate,CERTS/key)
    else:
        result=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        result.load_cert_chain(CERTS/certificate,CERTS/key)
        result.verify_mode=ssl.CERT_REQUIRED
        result.load_verify_locations(CERTS/f'{trust}.pem')
        result.num_tickets=0
    result.minimum_version=ssl.TLSVersion.TLSv1_2
    if version is not None: result.minimum_version=result.maximum_version=version
    return result


def invoke(role=0,mode=1,count=1025,layout=0,credential=None,key=None,password='-',trust='root.pem',
           peer_credential=None,peer_key=None,peer_trust='root',version=None,identity='localhost',
           fault=0,negative=False,trace=None,fail_at=None,fragment=0):
    global CASES
    if credential is None: credential='valid.pem' if role==0 else 'client.pem'
    if key is None: key='valid.key' if role==0 else 'client.key'
    if peer_credential is None: peer_credential='client.pem' if role==0 else 'valid.pem'
    if peer_key is None: peer_key='client.key' if role==0 else 'valid.key'
    parent,inherited=socket.socketpair();inherited.setblocking(False)
    if mode==2:
        inherited.setsockopt(socket.SOL_SOCKET,socket.SO_SNDBUF,4096)
        parent.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,4096)
    path=lambda name: str(CERTS/name) if name else ''
    ca=path(trust) if trust!='-' else '-'
    command=[str(EXE),str(inherited.fileno()),path(credential),path(key),password,ca,str(role),str(mode),str(count),str(layout),str(fault),identity]
    if trace:
        prefix=['strace','-qq','-o',str(trace),'-e','trace=mmap,munmap,write']
        if fail_at is not None: prefix += ['-e',f'inject=mmap:error=ENOMEM:when={fail_at}']
        command=prefix+command
    env=os.environ.copy();env['SSL_CERT_FILE']=str(CERTS/'root.pem');env['SSL_CERT_DIR']=str(CERTS/'no-native-directory')
    process=subprocess.Popen(command,pass_fds=(inherited.fileno(),),stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
    inherited.close();error=None;version_name=None;authenticated=False;served=0;has_ticket=None
    try:
        if mode not in (0,6,7,8):
            configuration=context(role,peer_credential,peer_key,peer_trust,version)
            peer=Client(parent,configuration,identity,fragment) if role==0 else Connection(parent,configuration,fragment)
            try:
                peer.handshake();authenticated=True;version_name=peer.tls.version()
                assert peer.tls.getpeercert(), 'native peer certificate is required'
                if role==0:
                    if mode==2:
                        assert process.stderr.readline(2)==b'W\n'
                        assert peer.read_exact(count)==bytes(value^90 for value in binary(count))
                        assert process.stderr.readline(2)==b'R\n'
                        peer.write(binary(count),chunk=293)
                    else:
                        peer.write(binary(count),chunk=293)
                        assert peer.read_exact(count)==bytes(value^90 for value in binary(count))
                    served=count
                    assert peer.read()==b''
                    has_ticket=peer.tls.session.has_ticket
                    peer.shutdown()
                else:
                    if mode==2: assert process.stderr.readline(2)==b'W\n'
                    assert peer.read_exact(count)==binary(count);served=count
                    if mode==2: assert process.stderr.readline(2)==b'R\n'
                    peer.write(bytes(value^90 for value in binary(count)),chunk=251)
                    assert peer.read()==b'';peer.shutdown()
            except (ssl.SSLError,OSError,EOFError) as exc:
                error=exc
                if not negative: raise
        status=process.wait(timeout=7)
        out=process.stdout.read(4096);err=process.stderr.read(4096)
        assert status==0 and len(out)==136 and err==(b'A\nB\n' if mode==0 else b''),(command,status,out,err)
        if negative: assert error is not None,(command,'expected native peer rejection')
        values=struct.unpack('<17Q',out);CASES+=1
        return values,dict(error=error,version=version_name,authenticated=authenticated,served=served,has_ticket=has_ticket)
    finally:
        parent.close()
        if process.poll() is None: process.kill();process.wait(timeout=1)
        process.stdin.close();process.stdout.close();process.stderr.close()


def success(values,count):
    assert values[:6]==(0,)*6 and values[8:10]==(count,count),values
    assert values[11]==5 and values[15:17]==(0,1) and values[12]>0,values


def matrix():
    for role in (0,1):
        for version in (ssl.TLSVersion.TLSv1_2,ssl.TLSVersion.TLSv1_3):
            for count,layout in ((1,0),(1025,1),(16385,2)):
                values,peer=invoke(role=role,version=version,count=count,layout=layout,fragment=7 if count==1 else 0)
                success(values,count)
                assert peer['version']==('TLSv1.2' if version==ssl.TLSVersion.TLSv1_2 else 'TLSv1.3')
                if role==0: assert peer['has_ticket'] is False
        values,_=invoke(role=role,trust='-');success(values,1025)
    for options in [dict(peer_credential='client-chain-full.pem',peer_key='client-chain.key'),
                    dict(peer_credential='client-alt.pem',peer_key='client-alt.key'),
                    dict(peer_credential='client-no-eku.pem',peer_key='client-no-eku.key')]:
        values,_=invoke(**options);success(values,1025)
    values,_=invoke(role=1,credential='client-chain-full.pem',key='client-chain.key',identity='127.0.0.1');success(values,1025)
    values,_=invoke(role=1,key='client-encrypted.key',password=PASSPHRASE);success(values,1025)
    print(f'openssl-mutual-tls matrix cases={CASES} roles=2 TLS1.2/1.3 DNS/IP chains layouts default/custom trust native-policy-receipts=true')


def verification():
    from verification_control import check
    assert check(CERTS)==19
    for version in (ssl.TLSVersion.TLSv1_2,ssl.TLSVersion.TLSv1_3):
        for certificate,key,code in [('client-untrusted.pem','client-untrusted.key',20),('client-expired.pem','client-expired.key',10),('client-wrong-purpose.pem','client-wrong-purpose.key',26),('client-chain.pem','client-chain.key',20),('','',0)]:
            values,peer=invoke(version=version,peer_credential=certificate,peer_key=key,negative=True)
            assert values[0]==1 and values[2]==7 and values[8:10]==(0,0) and values[11]==6 and values[16]==0,(certificate,values)
            assert values[15]==code,(certificate,values)
        # A Lanius client may locally finish TLS1.3 before the native server's
        # later rejection alert; either handshake or subsequent I/O must fail.
        values,peer=invoke(role=1,version=version,peer_trust='untrusted',negative=True)
        assert values[0] in (1,2,4) and values[11]==6 and values[9]==0 and peer['served']==0,values
        if version==ssl.TLSVersion.TLSv1_3: assert values[16] in (0,1)
    for options,code in [(dict(role=1,identity='wrong.invalid'),62),(dict(role=1,identity='127.0.0.2'),64),(dict(role=1,trust='untrusted.pem'),19),
                         (dict(role=1,peer_credential='expired.pem',peer_key='expired.key'),10),(dict(role=1,peer_credential='wrong-purpose.pem',peer_key='wrong-purpose.key'),26)]:
        values,peer=invoke(negative=True,**options)
        assert values[0:3]==(1,11,7) and values[15]==code and values[16]==0 and values[8:10]==(0,0),dict(case=options,expected_verify_code=code,observed=values)
    print(f'openssl-mutual-tls verification cases={CASES} invalid-client-server-never-open=true client-local-complete-is-not-remote-acceptance=true')


def credentials():
    for role in (0,1):
        values,_=invoke(role=role,mode=8);assert values==(0,)*17,values
        values,_=invoke(role=role,mode=6);assert values==(0,)*17,values
        for options,phases in [(dict(credential='missing.pem'),(11,)),(dict(key='missing.key'),(12,)),(dict(credential='malformed.pem'),(11,)),(dict(key='root.key'),(12,14)),(dict(trust='missing.pem'),(2,))]:
            values,_=invoke(role=role,mode=6,**options)
            assert values[0:2]==(6,10) and values[2] in phases and values[4]!=0 and values[16]==0,values
        for password in ('-', 'wrong password'):
            values,_=invoke(role=role,mode=6,credential='client.pem',key='client-encrypted.key',password=password)
            assert values[:3]==(6,10,12) and values[4]!=0,values
    print(f'openssl-mutual-tls credentials cases={CASES} metadata-preflight encrypted-key wrong-password missing/mismatch/trust no-interactive-stdin=true')


def faults():
    cases=[(1,1),(2,1),(3,3),(4,11),(5,12),(6,14),(7,4),(8,6),(9,7),(13,2),(14,2)]
    for role in (0,1):
        for fault,phase in cases:
            values,_=invoke(role=role,mode=7,fault=fault,trust='-' if fault==14 else 'root.pem')
            expected=6 if fault in (1,2,3,4,5,6,13,14) else 7 if fault in (7,8) else 1
            assert values[0]==expected and values[1:3]==(10,phase) and (values[4]&8388607)==400+fault and values[16]==0,values
        for fault,cause in ((19,11),(20,12)):
            values,_=invoke(role=role,fault=fault,negative=True,count=1)
            assert values[0:3]==(1,cause,7) and values[11]==6 and values[16]==0 and values[8:10]==(0,0),values
            if fault==19: assert values[15]==26 and (values[4]&8388607)==419
    for fault,cause in ((15,10),(16,10),(17,15),(18,15)):
        values,_=invoke(mode=7,fault=fault)
        assert values[0:3]==(6,cause,3) and (values[4]&8388607)==400+fault,values
    print(f'openssl-mutual-tls native-faults cases={CASES} exact-diagnostics context/session/fd-cleanup policy-postchecks=true')


def retries():
    for role in (0,1):
        for fault in (21,22):
            values,_=invoke(role=role,fault=fault,count=1025,layout=1)
            success(values,1025)
            assert values[13 if fault==21 else 14]>0,values
        values,_=invoke(role=role,mode=2,count=524288,layout=2)
        success(values,524288);assert values[7]>0 and values[13]>0 and values[14]>0,values
    print(f'openssl-mutual-tls retries cases={CASES} stable-write-copy/pointer changed-read-destination actual-backpressure guards=true')


def allocation_events(trace):
    active=False;ordinal=0;attempts=[];live={};failed=0
    for line in trace.splitlines():
        if line.startswith('write(2, "A\\n", 2)'): active=True
        elif line.startswith('write(2, "B\\n", 2)'): assert active and not live,(live,trace);active=False
        if line.startswith('mmap('):
            ordinal+=1
            if active and 'MAP_32BIT' in line:
                count=int(line.split(',')[1]);address=line.rsplit(' = ',1)[1].split()[0];attempts.append((ordinal,count))
                if address.startswith('0x'): assert address not in live;live[address]=count
                else: assert address=='-1' and 'ENOMEM' in line;failed+=1
        elif line.startswith('munmap('):
            match=re.match(r'munmap\((0x[0-9a-f]+), (\d+)\)\s+= 0',line)
            if match and match[1] in live: assert live.pop(match[1])==int(match[2]),line
    assert not active and not live,trace
    return attempts,failed


def allocations():
    with tempfile.TemporaryDirectory(prefix='mutual_tls_alloc_') as d:
        for role in (0,1):
            path=Path(d)/f'baseline{role}'
            values,_=invoke(role=role,mode=0,trace=path)
            assert values[0:11]==(0,)*11 and values[11]==1 and values[16]==0,values
            baseline,failed=allocation_events(path.read_text());assert len(baseline)==7+role and failed==0,(role,baseline)
            for index,(ordinal,_) in enumerate(baseline):
                path=Path(d)/f'fault{role}-{index}'
                values,_=invoke(role=role,mode=0,trace=path,fail_at=ordinal)
                attempts,failed=allocation_events(path.read_text())
                phase=(11,12,13,2)[index] if index<4 else (5 if role==1 and index==4 else 4)
                outcome=6 if index<4 else 7
                assert values[0:3]==(outcome,9,phase) and failed==1 and len(attempts)==index+1,(role,index,values,attempts)
    print(f'openssl-mutual-tls allocations cases={CASES} server7/client8-staging-positions exact-map-release=true')


if __name__=='__main__':
    group,executable,certificates=sys.argv[1:]
    EXE=Path(executable).resolve();CERTS=Path(certificates).resolve()
    globals()[group]()
