
const BASE=Deno.env.get('SUPABASE_URL'),KEY=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const H={apikey:KEY,Authorization:'Bearer '+KEY,'Content-Type':'application/json'};
const C={'Access-Control-Allow-Origin':'https://billy200027.github.io','Access-Control-Allow-Headers':'authorization,apikey,content-type','Access-Control-Allow-Methods':'GET,POST,OPTIONS','Content-Type':'application/json','Cache-Control':'no-store'};
const reply=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:C});
async function call(path,method='GET',data,token){const r=await fetch(BASE+path,{method,headers:{...H,...(token?{Authorization:'Bearer '+token}:{})},...(data!==undefined?{body:JSON.stringify(data)}:{})});const j=await r.json().catch(()=>({}));if(!r.ok)throw Error(j.message||j.error||'No se pudo completar la operación');return j;}
async function admin(req){
 const token=(req.headers.get('authorization')||'').replace(/^Bearer /i,'');if(!token)throw Error('Inicia sesión como administrador');
 const user=await call('/auth/v1/user','GET',undefined,token);
 const part=token.split('.')[1];const claims=JSON.parse(atob(part.replace(/-/g,'+').replace(/_/g,'/')));
 if(!claims.session_id||!await call('/rest/v1/rpc/finance_session_valid','POST',{p_user:user.id,p_session:claims.session_id}))throw Error('La sesión venció. Vuelve a ingresar');
 const result=await call('/rest/v1/rpc/finance_api','POST',{p_user:user.id,p_action:'status',p_data:{},p_key:null});
 if(result.member?.role!=='ADMIN'||result.member?.status!=='APROBADA'||result.member?.force_password)throw Error('Solo el administrador puede publicar archivos');
 return user;
}

const isUuid=value=>typeof value==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(value);
const isIdeaId=value=>Number.isSafeInteger(value)&&value>0;
const ideaRpc=(name,data)=>call('/rest/v1/rpc/'+name,'POST',data);
async function publicIdeas(data){
  if(!isUuid(data.browser))return reply({error:'No se pudo identificar este navegador. Recarga la página.'},400);
  if(data.action==='ideas-list'){
    if(data.before!=null&&!isIdeaId(data.before))return reply({error:'Página inválida'},400);
    return reply({ideas:await ideaRpc('portfolio_ideas_list',{p_browser:data.browser,p_before:data.before??null})});
  }
  if(data.action==='ideas-publish'){
    const body=typeof data.body==='string'?data.body.trim():'';
    if(!body||Array.from(body).length>4000||body.includes('\u0000')||!isUuid(data.request))return reply({error:'Escribe una idea de entre 1 y 4.000 caracteres.'},400);
    const result=await ideaRpc('portfolio_idea_publish',{p_browser:data.browser,p_request:data.request,p_body:body});
    if(result.limited)return reply({error:'Ya publicaste tres ideas en las últimas 24 horas. Vuelve a intentarlo más tarde.'},429);
    return reply(result,201);
  }
  if(!isIdeaId(data.id)||typeof data.liked!=='boolean')return reply({error:'Voto inválido'},400);
  const result=await ideaRpc('portfolio_idea_vote',{p_idea:data.id,p_browser:data.browser,p_liked:data.liked});
  return result.missing?reply({error:'Esta idea ya no está publicada.'},404):reply(result);
}

const APK_PART_BYTES=32*1024*1024;
const APK_SMALL_LIMIT=40*1024*1024;
const APK_LIMIT=100*1024*1024;
const bucketUrl=BASE+'/storage/v1/object/portfolio-public/';
const publicBucketUrl=BASE+'/storage/v1/object/public/portfolio-public/';
const validSlug=slug=>typeof slug==='string'&&/^[a-z][a-z0-9-]{0,79}$/.test(slug);
const validSplitSize=size=>Number.isInteger(size)&&size>APK_SMALL_LIMIT&&size<=APK_LIMIT;
const apkPath=(slug,upload)=>slug+'/apk/'+upload+'.apk';
const partPath=(path,part)=>path+'.part-'+part+'.apk';
function mediaItem(row){
  if(!row.apk_size_bytes)return {...row,url:publicBucketUrl+row.object_path};
  const parts=Array.from({length:Math.ceil(row.apk_size_bytes/APK_PART_BYTES)},(_,part)=>({
    url:publicBucketUrl+partPath(row.object_path,part),
    size:Math.min(APK_PART_BYTES,row.apk_size_bytes-part*APK_PART_BYTES)
  }));
  return {...row,parts};
}
async function uploadApkPart(form,file,slug){
  const upload=form.get('upload'),size=Number(form.get('size')),part=Number(form.get('part'));
  if(!validSlug(slug)||!isUuid(upload)||!validSplitSize(size)||form.get('part')===null
     ||!Number.isInteger(part)||part<0||part>=Math.ceil(size/APK_PART_BYTES)
     ||!(file instanceof File)||!file.name.toLowerCase().endsWith('.apk')
     ||file.size!==Math.min(APK_PART_BYTES,size-part*APK_PART_BYTES)){
    return reply({error:'Parte del APK inválida'},400);
  }
  if(part===0){
    const bytes=new Uint8Array(await file.slice(0,4).arrayBuffer());
    if(bytes[0]!==80||bytes[1]!==75||bytes[2]!==3||bytes[3]!==4)return reply({error:'Selecciona un APK válido'},400);
  }
  const path=partPath(apkPath(slug,upload),part);
  const response=await fetch(bucketUrl+path,{
    method:'POST',headers:{...H,'Content-Type':'application/vnd.android.package-archive','x-upsert':'false','Cache-Control':'public,max-age=31536000'},body:file
  });
  if(!response.ok){
    const error=await response.json().catch(()=>null);
    if(response.status!==409&&String(error?.statusCode)!=='409'){
      return reply({error:'No se pudo guardar esta parte del APK. Reintenta la subida.'},502);
    }
  }
  return reply({ok:true},201);
}
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:C});
 try{
 if(req.method==='GET'){
 const rows=await call('/rest/v1/portfolio_media?select=id,app_slug,kind,object_path,caption,sort_order,created_at,apk_size_bytes&deleted_at=is.null&order=sort_order.asc,created_at.asc&limit=1000');
 return reply({media:rows.map(mediaItem)});
 }
 if(req.method!=='POST')return reply({error:'Método no permitido'},405);
 const isJson=req.headers.get('content-type')?.startsWith('application/json');
 let data;
 if(isJson){
   if(Number(req.headers.get('content-length')||0)>32768)return reply({error:'Solicitud demasiado larga'},413);
   const raw=await req.text();
   if(raw.length>32768)return reply({error:'Solicitud demasiado larga'},413);
   try{data=JSON.parse(raw);}catch{return reply({error:'Solicitud inválida'},400);}
   if(!data||typeof data!=='object'||Array.isArray(data))return reply({error:'Solicitud inválida'},400);
   if(['ideas-list','ideas-publish','ideas-vote'].includes(data.action))return await publicIdeas(data);
 }
 try{await admin(req);}catch{return reply({error:'Acceso reservado al administrador. Inicia sesión de nuevo.'},401);}

 if(isJson){
 if(data.action==='apk-complete'){
   if(!validSlug(data.slug)||!isUuid(data.upload)||!validSplitSize(data.size))return reply({error:'APK inválido'},400);
   const id=await ideaRpc('portfolio_publish_split_apk',{
     p_slug:data.slug,p_upload:data.upload,p_size:data.size,
     p_caption:String(data.caption||'').slice(0,200),
     p_position:Number.isInteger(data.position)&&data.position>=0&&data.position<=1000000?data.position:0
   });
   return id?reply({ok:true,id},201):reply({error:'Faltan partes del APK. Reintenta la subida.'},409);
 }
 if(data.action==='ideas-hide'){
   if(!isIdeaId(data.id))return reply({error:'Idea inválida'},400);
   await call('/rest/v1/portfolio_ideas?id=eq.'+data.id+'&hidden_at=is.null','PATCH',{hidden_at:new Date().toISOString()});
   return reply({ok:true});
 }
 if(data.action==='admin-list'){const rows=await call('/rest/v1/portfolio_media?select=id,app_slug,kind,object_path,caption,sort_order,created_at,apk_size_bytes,deleted_at&order=sort_order.asc,created_at.asc&limit=1000');return reply({media:rows.map(mediaItem)});}
 if(!['remove','restore'].includes(data.action)||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(data.id||''))return reply({error:'Acción o archivo inválido'},400);
 const response=await fetch(BASE+'/rest/v1/portfolio_media?id=eq.'+data.id,{method:'PATCH',headers:{...H,Prefer:'return=representation'},body:JSON.stringify({deleted_at:data.action==='remove'?new Date().toISOString():null})});
 const rows=await response.json().catch(()=>null);
 if(!response.ok||!Array.isArray(rows))return reply({error:'No se pudo actualizar el archivo'},502);
 if(rows.length!==1)return reply({error:'El archivo ya no está disponible'},404);
 return reply({ok:true,removed:data.action==='remove'});
 }
 if(Number(req.headers.get('content-length')||0)>44040192)return reply({error:'Máximo 40 MB por archivo'},413);
 if(!req.headers.get('content-type')?.startsWith('multipart/form-data'))return reply({error:'Selecciona un archivo'},400);
 const form=await req.formData(),file=form.get('file'),slug=String(form.get('slug')||''),kind=String(form.get('kind')||'');
 if(kind==='apk-part')return await uploadApkPart(form,file,slug);
 if(!/^[a-z][a-z0-9-]{0,79}$/.test(slug)||!['screenshot','logo','apk'].includes(kind))return reply({error:'Aplicación o tipo inválido'},400);
 if(!(file instanceof File)||file.size===0||file.size>41943040)return reply({error:'Usa un archivo de hasta 40 MB'},400);
 const signature=new Uint8Array(await file.slice(0,16).arrayBuffer());let mime='',ext='';
 if(kind==='apk'){if(!file.name.toLowerCase().endsWith('.apk')||signature[0]!==80||signature[1]!==75||signature[2]!==3||signature[3]!==4)return reply({error:'Selecciona un APK válido'},400);mime='application/vnd.android.package-archive';ext='apk';}
 else if(signature[0]===137&&signature[1]===80&&signature[2]===78&&signature[3]===71&&signature[4]===13&&signature[5]===10&&signature[6]===26&&signature[7]===10){mime='image/png';ext='png';}
 else if(signature[0]===255&&signature[1]===216&&signature[2]===255){mime='image/jpeg';ext='jpg';}
 else if(String.fromCharCode(...signature.slice(0,4))==='RIFF'&&String.fromCharCode(...signature.slice(8,12))==='WEBP'){mime='image/webp';ext='webp';}
 else return reply({error:'Usa una imagen JPG, PNG o WebP'},400);
 const path=slug+'/'+kind+'/'+crypto.randomUUID()+'.'+ext;
 const uploaded=await fetch(BASE+'/storage/v1/object/portfolio-public/'+path,{method:'POST',headers:{...H,'Content-Type':mime,'x-upsert':'false','Cache-Control':'public,max-age=31536000'},body:file});
 if(!uploaded.ok)return reply({error:'No se pudo subir el archivo. Inténtalo nuevamente.'},502);
 const position=Number(form.get('position')||0);
 const row={app_slug:slug,kind,object_path:path,caption:String(form.get('caption')||'').slice(0,200),sort_order:Number.isInteger(position)&&position>=0&&position<=1000000?position:0};
 try{await call('/rest/v1/portfolio_media','POST',row);}catch(e){await call('/storage/v1/object/portfolio-public','DELETE',{prefixes:[path]}).catch(()=>{});throw e;}
 return reply({ok:true,url:BASE+'/storage/v1/object/public/portfolio-public/'+path},201);
 }catch{return reply({error:'No se pudo completar la operación. Revisa tu sesión o vuelve a intentar.'},500);}
});
