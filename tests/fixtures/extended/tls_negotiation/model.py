#!/usr/bin/env python3
"""Independent, declarative TLS wire/policy oracle. No production backend."""
import hashlib, ipaddress, random, re, struct, sys
W=(1<<64)-1
HRR=bytes.fromhex('cf21ad74e59a6111be1d8c021e65b891c2a211167abb8c5e079e09e2c8a8339c')
u16=lambda n:struct.pack('!H',n)
vec=lambda b:u16(len(b))+b
ext=lambda k,b:u16(k)+vec(b)
words=lambda ns:b''.join(u16(n) for n in ns)
ALPN=b'\x02h2\x08http/1.1'
SHARE=bytes(range(32))
class Failure(Exception):
 def __init__(self,code):self.code=code

def require(b,c):
 if not b:raise Failure(c)
def extensions(raw):
 result=[];pos=0;seen=set()
 while pos<len(raw):
  require(pos+4<=len(raw),102);kind,n=struct.unpack_from('!HH',raw,pos);pos+=4
  require(n<=len(raw)-pos,102);require(kind not in seen,106);seen.add(kind)
  result.append((kind,raw[pos:pos+n]));pos+=n
 return result

def base_extensions(share=SHARE,groups=(29,),sigs=(2055,),cert=(2055,),sni=b'example.com',alpn=ALPN,cookie=b'',extra=()):
 result=[(43,b'\x02\x03\x04'),(10,vec(words(groups))),(13,vec(words(sigs)))]
 if cert is not None:result.append((50,vec(words(cert))))
 result.append((51,vec(b'' if share is None else u16(29)+vec(share))))
 if sni is not None:result.append((0,vec(b'\x00'+vec(sni))))
 if alpn is not None:result.append((16,vec(alpn)))
 if cookie:result.append((44,vec(cookie)))
 return result+list(extra)
def ch(es=None,random_bytes=b'R'*32,session=b'abc',suites=(4865,4867)):
 if es is None:es=base_extensions()
 raw=b''.join(ext(k,d) for k,d in es)
 return b'\x03\x03'+random_bytes+bytes([len(session)])+session+vec(words(suites))+b'\x01\x00'+vec(raw)
def sh(es=None,random_bytes=b'S'*32,session=b'abc',suite=4867):
 if es is None:es=[(43,b'\x03\x04'),(51,u16(29)+vec(SHARE))]
 raw=b''.join(ext(k,d) for k,d in es)
 return b'\x03\x03'+random_bytes+bytes([len(session)])+session+u16(suite)+b'\x00'+vec(raw)
def ee(es=()):return vec(b''.join(ext(k,d) for k,d in es))
class Reader:
 def __init__(self,b):self.b=b;self.p=0
 def take(self,n):
  require(n<=len(self.b)-self.p,102);b=self.b[self.p:self.p+n];self.p+=n;return b
 def num(self,n):return int.from_bytes(self.take(n),'big')
 def vector(self,n,low=0,high=65535):
  size=self.num(n);require(low<=size<=high,103);return self.take(size)
 def done(self):require(self.p==len(self.b),103)
def parse_ch(raw):
 r=Reader(raw);require(r.num(2)==771,105);random_bytes=r.take(32);session=r.vector(1,0,32);suites=r.vector(2,2,65534);require(len(suites)%2==0,103);require(r.vector(1,1,1)==b'\0',105);es=r.vector(2);r.done();items=extensions(es);mapping=dict(items)
 require(43 in mapping,107);d=mapping[43];v=Reader(d);versions=v.vector(1,2,254);v.done();require(len(versions)%2==0,103);require(b'\x03\x04' in [versions[i:i+2] for i in range(0,len(versions),2)],105)
 return dict(random=random_bytes,session=session,suites=list(struct.unpack('!'+'H'*(len(suites)//2),suites)),suitebytes=suites,items=items,es=es)
def parse_sh(raw):
 r=Reader(raw);require(r.num(2)==771,105);random_bytes=r.take(32);session=r.vector(1,0,32);suite=r.num(2);require(r.num(1)==0,105);es=r.vector(2);r.done();items=extensions(es);m=dict(items);require(43 in m,107);require(len(m[43])==2,103);require(m[43]==b'\x03\x04',105)
 return dict(random=random_bytes,session=session,suite=suite,items=items,es=es)
def list16(d):
 require(len(d)>=2,5);n=int.from_bytes(d[:2],'big');require(n==len(d)-2 and n>0 and n%2==0,5)
 return list(struct.unpack('!'+'H'*(n//2),d[2:]))
def protocols(d):
 require(2<=len(d)<=65533,14);result=[];at=0
 while at<len(d):
  n=d[at];at+=1;require(n>0 and at+n<=len(d),14);result.append(d[at:at+n]);at+=n
 return result

def host(d):
 require(1<=len(d)<=253 and not d.endswith(b'.'),15)
 require(all(re.fullmatch(rb'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?',label) is not None for label in d.split(b'.')),15)
 try:ipaddress.ip_address(d.decode('ascii'))
 except ValueError:pass
 else:raise Failure(15)

def inspect(p,allow_cookie=False):
 m=dict(p['items']);require(not (set(m)&{41,42,19,20,49}),7);require(48 not in m,5)
 for k in (43,10,13,51):require(k in m,4)
 groups=list16(m[10]);require(len(set(groups))==len(groups),6);sigs=list16(m[13]);cert=list16(m[50]) if 50 in m else sigs
 d=m[51];require(len(d)>=2 and int.from_bytes(d[:2],'big')==len(d)-2,5);d=d[2:];shares=[];keys={}
 while d:
  require(len(d)>=4,5);g,n=struct.unpack_from('!HH',d);d=d[4:];require(n>0 and n<=len(d),5);require(g not in keys,6);keys[g]=d[:n];shares.append(g);d=d[n:]
 require(all(g in groups for g in shares),12);require([groups.index(g) for g in shares]==sorted(groups.index(g) for g in shares),12)
 if 29 in keys:require(len(keys[29])==32,5)
 server_name=b''
 if 0 in m:
  d=m[0];require(len(d)>=5 and int.from_bytes(d[:2],'big')==len(d)-2,15);d=d[2:];seen=set()
  while d:
   require(len(d)>=3,15);kind=d[0];n=int.from_bytes(d[1:3],'big');d=d[3:];require(n>0 and n<=len(d),15);require(kind not in seen,6);seen.add(kind)
   if kind==0:server_name=d[:n];host(server_name)
   d=d[n:]
 alpn=b''
 if 16 in m:
  d=m[16];require(len(d)>=2 and int.from_bytes(d[:2],'big')==len(d)-2,14);alpn=d[2:];protocols(alpn)
 cookie=b''
 if 44 in m:
  require(allow_cookie,13);d=m[44];require(len(d)>=3 and int.from_bytes(d[:2],'big')==len(d)-2,5);cookie=d[2:]
 if 45 in m:require(len(m[45])>=2 and m[45][0]==len(m[45])-1,5)
 if 21 in m:require(not any(m[21]),5)
 return dict(p,groups=groups,sigs=sigs,cert=cert,keys=keys,shares=shares,keybytes=m[51][2:],sni=server_name,alpn=alpn,cookie=cookie)
def witness(b):return list(struct.unpack('<4Q',hashlib.sha256(b).digest()))
def offer_summary(p):return [0,0,0,0,0,len(p['keys'].get(29,b'')),len(p['cookie']),len(p['sni']),len(p['alpn']),0,W,0]+witness(p['keys'].get(29,b''))+witness(p['cookie'])+witness(p['sni'])+witness(p['alpn'])
def selection(suite,group,retry,key=b'',cookie=b''):return [0,suite,group,2055,int(retry),len(key),len(cookie),0,0,0,W,0]+witness(key)+witness(cookie)+[0]*8
def writer(sub,group,flag,a,b,c,d):
 if sub==0:
  require(len(a) in (0,32) and len(b)<=253 and len(c)<=65533 and len(d)<=65533,5)
  if b:host(b)
  if c:protocols(c)
  es=base_extensions(a or None,sni=b or None,alpn=c or None,cookie=d)
 elif sub==1:require(len(a)==32,5);es=[(43,b'\x03\x04'),(51,u16(29)+vec(a))]
 elif sub==2:
  require(group in (0,29) and len(d)<=65533 and (group or d),13);es=[(43,b'\x03\x04')]
  if group:es.append((51,u16(group)))
  if d:es.append((44,vec(d)))
 else:
  require(len(c)<=255,14);es=[]
  if flag:es.append((0,b''))
  if c:es.append((16,vec(bytes([len(c)])+c)))
 return b''.join(ext(k,d) for k,d in es)
def expected(h,blobs):
 op,layout,mode,pref,group,flag,limit,work,capacity,*_=h;a,b,c,d=blobs;result=[0]*28;result[10]=W;extra=[]
 try:
  if op==6:
   require(mode!=3 and not(mode==1 and pref in (0,1)) and not(mode==2 and pref==0),1)
   # Capacity precedes detailed syntax and work in writer preflight. Shape
   # failures are checked before total/capacity, as documented publicly.
   n={0:37+(36 if a else 0)+(9+len(b) if b else 0)+(6+len(c) if c else 0)+(6+len(d) if d else 0),1:46,2:6+(6 if group else 0)+(6+len(d) if d else 0),3:(4 if flag else 0)+(7+len(c) if c else 0)}[pref]
   if pref==0:require(len(a) in (0,32) and len(b)<=253 and len(c)<=65533 and len(d)<=65533,5)
   if pref==1:require(len(a)==32,5)
   if pref==2:require(group in (0,29) and len(d)<=65533 and (group or d),13)
   if pref==3:require(len(c)<=255,14)
   require(n<=65535,5);require(capacity>=n,17);require(mode!=5,1);require(n<=limit,2);require(work>=8*n+8,3)
   wire=writer(pref,group,flag,a,b,c,d);assert len(wire)==n;result[11]=n
  else:
   require(mode!=1,101);p=parse_ch(a);require(mode!=3,1);require(mode!=5,1)
   require(len(p['random'])+len(p['session'])+len(p['suitebytes'])+len(p['es'])<=limit,2);require(work>=4096+8*(32+len(p['session'])+len(p['suitebytes'])+len(p['es'])),3)
   p=inspect(p,mode==6)
   if op==0:result=offer_summary(p)
   if op==1:
    require(pref in (4865,4867),8);suite=pref if pref in p['suites'] else (4867 if pref==4865 else 4865);require(suite in p['suites'],8);require(29 in p['groups'],9);require(2055 in p['sigs'] and 2055 in p['cert'],10);result=selection(suite,29,29 not in p['keys'],p['keys'].get(29,b''))
   if op==2:
    require(mode!=2,101);s=parse_sh(b);require(s['session']==p['session'],11);require(s['suite'] in (4865,4867) and s['suite'] in p['suites'],12);retry=s['random']==HRR
    require(flag or not p['cookie'],13)
    if flag:require(not retry and pref==s['suite'] and group in (0,29) and len(c)<=65533 and (group or c) and c==p['cookie'],13)
    m=dict(s['items']);require(not(set(m)&{41,42}),7);bad=set(m)-{43,51}-({44} if retry else set())
    if bad:raise Failure(12 if any(k not in dict(p['items']) for k in bad) else 5)
    g=0;key=b'';cookie=b''
    if 51 in m:
     if retry:require(len(m[51])==2,5);g=int.from_bytes(m[51],'big');require(g==29 and g in p['groups'] and 29 not in p['keys'],13)
     else:require(len(m[51])==36 and m[51][:4]==b'\x00\x1d\x00\x20' and 29 in p['keys'],12);g=29;key=m[51][4:]
    if retry and 44 in m:require(len(m[44])>=3 and int.from_bytes(m[44][:2],'big')==len(m[44])-2,5);cookie=m[44][2:]
    if retry:require(g or cookie,13);require(g or 29 in p['keys'],9)
    else:require(g==29,4);require(not flag or not group or group==g,13)
    require(2055 in p['sigs'] and 2055 in p['cert'],10);result=selection(s['suite'],g,retry,key,cookie)
   if op==3:
    require(group in (0,29) and pref in (4865,4867) and len(c)<=65533,13);require(mode!=2,101);q=inspect(parse_ch(b),True)
    require(pref in p['suites'] and (group or (c and 29 in p['keys'])) and (group!=29 or (29 in p['groups'] and 29 not in p['keys'])),13)
    require(all(p[k]==q[k] for k in ('random','session','suitebytes')) and q['cookie']==c,16)
    require(group!=29 or (len(q['keybytes'])==36 and len(q['keys'].get(29,b''))==32),16)
    filter_es=lambda x:[(k,None if group and k==51 else d) for k,d in x['items'] if k not in {21,44}]
    require(filter_es(p)==filter_es(q),16);result=offer_summary(q)
   if op==4:
    require(mode!=2,101);r=Reader(b);es=r.vector(2);r.done();items=extensions(es);m=dict(items);require(not(set(m)&{41,42}),7)
    for k,d in items:
     require(k in dict(p['items']),12)
     if k==0:require(p['sni'] and not d,15);result[9]=1
     elif k==16:require(len(d)>=4 and int.from_bytes(d[:2],'big')==len(d)-2 and d[2]==len(d)-3 and d[2]!=0,14);require(d[3:] in protocols(p['alpn']),14);result[8]=len(d)-3
     elif k==10:g=list16(d);require(len(set(g))==len(g),6)
     else:raise Failure(5)
    chosen=m.get(16,b'\0\0\0')[3:];require(not c or c==chosen,14);result[24:28]=witness(chosen)
   if op==5:
    require(len(c)<=255,14);found=c and c in (protocols(p['alpn']) if p['alpn'] else []);require(found or not flag,14);result[8]=len(c) if found else 0;result[24:28]=witness(c if found else b'')
 except Failure as e:result=[e.code]+[0]*9+[W,0]+[0]*16;wire=b''
 if op==6:
  output=bytearray(b'\xa5'*1024)
  if result[0]==0:output[3:3+len(wire)]=wire
  extra=list(struct.unpack('<128Q',output))
 return result+extra

CASES=[]
def add(op=0,a=None,b=b'',c=b'',d=b'',pref=4867,group=0,flag=0,mode=0,limit=262144,work=16777216,capacity=1016,layouts=(0,1)):
 if a is None:a=ch()
 for layout in layouts:
  h=[op,layout,mode,pref,group,flag,limit,work,capacity,len(a),len(b),len(c),len(d)];blobs=[a,b,c,d];wire=struct.pack('<13Q',*h)+b''.join(blobs);CASES.append((wire,expected(h,blobs)))
def replace(es,k,d):return [(t,d if t==k else b) for t,b in es]
def omit(es,k):return [(t,b) for t,b in es if t!=k]
def offers():
 rng=random.Random(0x84467301)
 for i in range(72):
  groups=rng.sample([23,24,29,256,0xaaaa],rng.randrange(1,6));share=SHARE if 29 in groups and rng.randrange(2) else None;sigs=rng.sample([2055,1027,2052],rng.randrange(1,4));cert=None if i%3==0 else rng.sample([2055,1027],rng.randrange(1,3));suites=rng.sample([4865,4867,4866,0xaaaa],rng.randrange(1,5));alpn=[ALPN,b'\x03foo',b'\x01\0',None][i%4];es=base_extensions(share,groups,sigs,cert,alpn=alpn,extra=[(0xaaaa,b'opaque'),(45,b'\x01\x01')]);a=ch(es,suites=suites)
  add(0,a);add(1,a,pref=[4865,4867][i%2])
 for k in (10,13,51,50):
  add(0,ch(omit(base_extensions(),k)))
 for k,d in [(10,b'\0\0'),(10,vec(words([29,29]))),(13,b'\0\1\x08'),(50,vec(words([1027]))),(51,vec(u16(29)+vec(b'x'))),(51,vec(u16(30)+vec(SHARE))),(51,vec((u16(29)+vec(SHARE))*2)),(16,vec(b'')),(16,vec(b'\0')),(16,vec(b'\x04abc')),(0,vec(b'\0'+vec(b'bad..name'))),(0,vec(b'\0'+vec(b'example.com.'))),(0,vec(b'\0'+vec(b'127.0.0.1'))),(0,vec(b'\0'+vec(b'a')+b'\0'+vec(b'b'))),(45,b'\x02\x01'),(21,b'\0\1'),(48,b''),(41,b''),(42,b''),(49,b'')]:add(0,ch(replace(base_extensions(),k,d) if any(t==k for t,_ in base_extensions()) else base_extensions(extra=[(k,d)])))
 for sni in [b'1.example',b'123.456',b'XN--bcher-kva.example',b'a'*63+b'.test',b'\0test',b'*.example',b'-a.test',b'a_.test',b'\xff.test']:
  add(0,ch(base_extensions(sni=sni)))
 for groups,shares in [([23,29],[(23,b'p'),(29,SHARE)]),([23,29],[(29,SHARE),(23,b'p')]),([23,24,29],[(23,b'p'),(29,SHARE)]),([29],[])]:
  es=replace(base_extensions(groups=groups),51,vec(b''.join(u16(k)+vec(d) for k,d in shares)));add(0,ch(es));add(1,ch(es))
 add(0,ch(base_extensions(alpn=b'\x02h2\x02h2')))
 add(0,ch(base_extensions(cookie=b'unsolicited')))
 add(0,ch(replace(base_extensions(),0,vec(b'\x01'+vec(b'opaque')))))
 add(0,ch(replace(base_extensions(),0,vec(b'\x01'+vec(b'a')+b'\x01'+vec(b'b')))))
 groups=list(range(2048))+[65535];shares=[(g,SHARE if g==29 else b'x') for g in [0,29,63,64,1023,1024,2047,65535]]
 add(1,ch(replace(base_extensions(groups=groups),51,vec(b''.join(u16(g)+vec(d) for g,d in shares)))))
 for mode in (1,3,4,5):add(1,mode=mode)
 for limit in (0,64,128):add(0,limit=limit)
 for work in (0,1,4095):add(0,work=work)
 for n in (0,1,2,10,40,len(ch())-1):add(0,ch()[:n])
 add(0,ch(base_extensions(extra=[(13,vec(words([2055])))])))
def servers():
 for first_share in (None,SHARE):
  a=ch(base_extensions(first_share))
  for suite in (4865,4867,4866):
   add(2,a,sh(suite=suite));add(2,a,sh([(43,b'\x03\x04'),(51,u16(29))],HRR,suite=suite));add(2,a,sh([(43,b'\x03\x04'),(44,vec(b'cookie'))],HRR,suite=suite))
  for es in [[(43,b'\x03\x04')],[(43,b'\x03\x04'),(51,u16(23))],[(43,b'\x03\x04'),(51,u16(29)+vec(b'x'))],[(43,b'\x03\x04'),(44,vec(b'c'))],[(43,b'\x03\x04'),(16,vec(b'\x02h2'))],[(43,b'\x03\x04'),(0,b'')],[(43,b'\x03\x04'),(41,b'')],[(43,b'\x03\x04'),(0xaaaa,b'')]]:
   add(2,a,sh(es));add(2,a,sh(es,HRR))
  add(2,a,sh(session=b'bad'));add(2,a,sh(),flag=1,pref=4865,group=29,c=b'cookie');add(2,a,sh(),flag=1,group=29,c=b'cookie');add(2,a,sh([(43,b'\x03\x04'),(51,u16(29))],HRR),flag=1,group=29)
  for cookie in (b'',b'cookie',b'\0\xff'):
   first=base_extensions(first_share,extra=[(0xaaaa,b'unchanged'),(21,b'\0'*3)])
   for g in (0,29):
    second=base_extensions(SHARE if g else first_share,cookie=cookie,extra=[(0xaaaa,b'unchanged'),(21,b'\0')]);add(3,ch(first),ch(second),cookie,group=g)
    for k,d in [(0,vec(b'\0'+vec(b'changed.test'))),(13,vec(words([1027]))),(0xaaaa,b'changed'),(51,vec(b'')),(44,vec(b'wrong'))]:
     es=replace(second,k,d) if any(t==k for t,_ in second) else second+[(k,d)];add(3,ch(first),ch(es),cookie,group=g)
    add(3,ch(first),ch(second,suites=(4867,4865)),cookie,group=g);add(3,ch(first),ch(omit(second,50)),cookie,group=g);add(3,ch(first),ch(omit(second,51)+[(51,dict(second)[51])]),cookie,group=g);add(3,ch(first),ch(second,random_bytes=b'X'*32),cookie,group=g);add(3,ch(first),ch(second,session=b'different'),cookie,group=g)
 add(2,ch(base_extensions(extra=[(0xaaaa,b'offer')])),sh([(43,b'\x03\x04'),(51,u16(29)+vec(SHARE)),(0xaaaa,b'response')]))
 for prior_cookie,flag,g in [(b'cookie',1,29),(b'wrong',1,29),(b'',0,0),(b'cookie',1,0)]:
  add(2,ch(base_extensions(cookie=b'cookie')),sh(),prior_cookie,b'forged-descriptor',group=g,flag=flag,mode=6)
 for es in [[],[(0,b'')],[(16,vec(b'\x02h2'))],[(0,b''),(16,vec(b'\x02h2'))],[(16,vec(b'\x02h3'))],[(16,vec(b'\x02h2\x03foo'))],[(16,b'\0\1\0')],[(0,b'notempty')],[(10,vec(words([23,29])))],[(43,b'\x03\x04')],[(51,b'')],[(42,b'')],[(0xaaaa,b'')]]:
  for req in (b'',b'h2',b'http/1.1'):add(4,b=ee(es),c=req)
 for alpn in (None,ALPN,b'\x01\0\x03foo'):
  for pref in (b'',b'h2',b'h3',b'\0',b'foo'):
   for required in (0,1):add(5,ch(base_extensions(alpn=alpn)),c=pref,flag=required)
 add(4,b=ee([(0,b''),(0,b'')]))
 add(4,ch(base_extensions(sni=None)),ee([(0,b'')]))
 add(4,ch(base_extensions(alpn=None)),ee([(16,vec(b'\x02h2'))]))
def writers():
 for share in (b'',SHARE,b'x',b'x'*33):
  for name in (b'',b'example.com',b'example.com.',b'127.0.0.1'):
   for alpn in (b'',ALPN,b'\0'):
    add(6,share,name,alpn,b'cookie',pref=0)
 for sub in range(4):
  args=dict(op=6,a=SHARE,b=b'example.com',c=b'h2' if sub==3 else ALPN,d=b'cookie',pref=sub,group=29,flag=1)
  for cap in (0,8,45,46,72,73,1016):add(**args,capacity=cap)
  for mode in (1,2,3,5):add(**args,mode=mode)
  for work in (0,1):add(**args,work=work)
  add(**args,limit=0)
 for sub,aa,bb,cc,dd,gg,ff in [(0,b'',b'',b'',b'',0,0),(0,SHARE,b'example.com',ALPN,b'cookie',0,0),(1,SHARE,b'',b'',b'',0,0),(2,b'',b'',b'',b'cookie',29,0),(3,b'',b'',b'h2',b'',0,1)]:
  n=len(writer(sub,gg,ff,aa,bb,cc,dd))
  for cap in (n-1,n,n+1):add(6,a=aa,b=bb,c=cc,d=dd,pref=sub,group=gg,flag=ff,capacity=cap)
 for group in (0,23,29):
  for cookie in (b'',b'c',b'\0\xff'):add(6,a=b'',d=cookie,pref=2,group=group)
 for alpn in (b'',b'\0',b'x'*255,b'x'*256):
  for flag in (0,1):add(6,a=b'',c=alpn,pref=3,flag=flag)
 add(6,a=SHARE,c=b'\xff'+b'X'*255,pref=0)

def main():
 mode=sys.argv[1]
 if mode=='offers':offers()
 elif mode=='server':servers()
 elif mode=='writers':writers()
 else:raise ValueError(mode)
 out=sys.stdout.buffer;out.write(struct.pack('<Q',len(CASES)))
 for wire,result in CASES:out.write(struct.pack('<Q',len(wire))+wire+struct.pack('<Q',len(result))+struct.pack('<'+'Q'*len(result),*result))
if __name__=='__main__':main()
