import hashlib,hmac,struct,sys
source=sys.stdin.buffer.read();at=0
def words(n):
 global at
 v=struct.unpack_from('<'+'Q'*n,source,at);at+=8*n;return v
def take(n):
 global at
 v=source[at:at+n];assert len(v)==n;at+=n;return v
def H(b):return function(b).digest()
def mac(k,b):return hmac.new(k,b,function).digest()
def expand(k,label,ctx,n):
 label=b'tls13 '+label;info=struct.pack('>H',n)+bytes([len(label)])+label+bytes([len(ctx)])+ctx;out=b'';prev=b''
 for i in range(1,(n+size-1)//size+1):prev=mac(k,prev+info+bytes([i]));out+=prev
 return out[:n]
def derive(k,label,th):return expand(k,label,th,size)
def finished(k,th):return mac(expand(k,b'finished',b'',size),th)
def q(*a):return struct.pack('<'+'Q'*len(a),*a)
magic=bytes.fromhex('cf21ad74e59a6111be1d8c021e65b891c2a211167abb8c5e079e09e2c8a8339c')
count,=words(1)
for _ in range(count):
 op,layout,alen,blen,clen,n,mode,algorithm=words(8);function=hashlib.sha256 if algorithm==0 else hashlib.sha384;size=function().digest_size;a,b,c=take(alen),take(blen),take(clen);status=0;out=b''
 if op==0:
  if mode:status=1
  elif len(a)!=size:status=2
  elif not 1<=len(b)<=249:status=4
  elif len(c)>255:status=5
  elif n>255*size:status=6
  else:out=expand(a,b,c,n)
 elif op in (1,3):
  ch,sh,sf,cf,before=[c[i:i+size] for i in range(0,5*size,size)];empty=H(b'');early=mac(bytes(size),bytes(size) if mode&1 else a);hs=mac(derive(early,b'derived',empty),bytes(size) if mode&2 else b);master=mac(derive(hs,b'derived',empty),bytes(size))
  client=derive(hs,b'c hs traffic',sh);server=derive(hs,b's hs traffic',sh);ex=derive(master,b'exp master',sf);res=derive(master,b'res master',cf);ee=derive(early,b'e exp master',ch)
  values=[early,derive(early,b'ext binder',empty),derive(early,b'res binder',empty),derive(early,b'c e traffic',ch),ee,hs,client,server,master,derive(master,b'c ap traffic',sf),derive(master,b's ap traffic',sf),ex,res,expand(res,b'resumption',bytes({0:0,1:1,size+1:255}.get(n,2)),size),finished(server,before),finished(client,sf),expand(client,b'traffic upd',b'',size)]
  out=b''.join(values)+expand(derive(ex,b'test export',empty),b'exporter',H(a),n)+expand(derive(ee,b'test export',empty),b'exporter',H(a),n)
 elif op==2:
  state=(b'',0,0,False);fork=state;pos=0
  while pos<len(a):
   action=a[pos];frame_size=int.from_bytes(a[pos+1:pos+3],'little');frame=a[pos+3:pos+3+frame_size];pos+=3+frame_size;raw,count,first,hrr=state;error=0
   if action in (0,1,5,6,7):
    if action==5:error=1
    elif len(frame)<4 or len(frame)!=int.from_bytes(frame[1:4],'big')+4:error=2
    elif action==1:
     if len(frame)<38 or frame[0]!=2 or frame[6:38]!=magic:error=2
     elif hrr or count!=1 or first!=1:error=4
     else:state=(bytes([254,0,0,size])+H(raw)+frame,2,first,True)
    elif frame[0]==254:error=3
    elif action in (6,7):error=5
    else:state=(raw+frame,count+1,frame[0] if count==0 else first,hrr)
   if action==3:fork=state
   if action==4:state,fork=fork,state
   raw,count,first,hrr=state;out+=q(error,count,int(hrr))+H(raw)
 else:raise AssertionError(op)
 sys.stdout.buffer.write(q(status,len(out))+out)
assert at==len(source)
