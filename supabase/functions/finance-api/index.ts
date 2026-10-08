// Sin dependencias. Secretos únicamente en el entorno privado de Supabase.
const URL=Deno.env.get('SUPABASE_URL')!, KEY=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const headers={'apikey':KEY,'Authorization':`Bearer ${KEY}`,'Content-Type':'application/json'};
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type','Access-Control-Allow-Methods':'POST,OPTIONS','Content-Type':'application/json','Cache-Control':'no-store'};
async function call(path:string,data?:unknown,method='POST',token?:string){const r=await fetch(URL+path,{method,headers:{...headers,...(token?{Authorization:`Bearer ${token}`}:{})},...(data!==undefined?{body:JSON.stringify(data)}:{})});const j=await r.json().catch(()=>({}));if(!r.ok)throw new Error(j.message||j.msg||j.error_description||'No fue posible completar la operación');return j;}
const rpc=(user:string|null,action:string,data={},key:string|null=null)=>call('/rest/v1/rpc/finance_api',{p_user:user,p_action:action,p_data:data,p_key:key});
async function digest(v:string){return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(v)))].map(x=>x.toString(16).padStart(2,'0')).join('');}
const internalEmail=async(id:string)=>(await digest('finance-billy:'+id))+'@finance-billy.invalid';
const ids=(s:unknown)=>String(s??'').replace(/\s/g,'');
const actions=new Set(['state','status','request','cancel_request','quote','admin_request','admin_disburse','admin_receipt','admin_member','admin_points','profile','admin_news','admin_bank','admin_settings','admin_correct_date']);
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 const respond=(j:unknown,status=200)=>new Response(JSON.stringify(j),{status,headers:cors});
 if(req.method!=='POST')return respond({error:'Método no permitido'},405);
 try{
 if(Number(req.headers.get('content-length')||0)>7500000)return respond({error:'Archivo demasiado grande'},413);
 const body=await req.json(),action=body.action,data=body.data||{},key=body.key||null;
 if(['login','signup','public','refresh'].includes(action)){
 const ip=req.headers.get('x-forwarded-for')?.split(',')[0]||'unknown';
 const allowed=await call('/rest/v1/rpc/finance_throttle',{p_key:await digest(action+':'+ip+':'+ids(data.cedula)),p_limit:action==='public'?100:20});if(!allowed)return respond({error:'Demasiados intentos. Espera 15 minutos.'},429);
 if(action==='public')return respond(await rpc(null,'public'));
 if(action==='refresh')return respond(await call('/auth/v1/token?grant_type=refresh_token',{refresh_token:data.refresh_token}));
 const cedula=ids(data.cedula);if(!/^[0-9]{6,15}$/.test(cedula))throw Error('Escribe tu cédula sin espacios');
 const email=await internalEmail(cedula);
 if(action==='login'){
 try{return respond(await call('/auth/v1/token?grant_type=password',{email,password:data.password}));}catch{return respond({error:'Cédula o contraseña incorrectas'},401);}
 }
 if(String(data.password||'').length<10)throw Error('La contraseña necesita al menos 10 caracteres');
 if(!Array.isArray(data.accounts)||data.accounts.length<1||data.accounts.length>2||String(data.name||'').trim().length<5)throw Error('Completa el nombre y una o dos cuentas bancarias');
 let created:string|undefined;
 try{
 const user=await call('/auth/v1/admin/users',{email,password:data.password,email_confirm:true,user_metadata:{app:'finance-billy'}});created=user.id;
 await rpc(created!,'register',{...data,password:undefined,cedula});
 }catch(e){if(created)await call('/auth/v1/admin/users/'+created,undefined,'DELETE').catch(()=>{});return respond({error:'No se pudo registrar. Revisa los datos; la cédula puede estar registrada.'},400);}
 return respond({ok:true,status:'PENDIENTE'});
 }
 const token=req.headers.get('authorization')?.replace(/^Bearer /i,'');if(!token) return respond({error:'Inicia sesión'},401);
 const user=await call('/auth/v1/user',undefined,'GET',token);
 const claims=JSON.parse(atob(token.split('.')[1].replace(/-/g,'+').replace(/_/g,'/')));
 if(!claims.session_id||!await call('/rest/v1/rpc/finance_session_valid',{p_user:user.id,p_session:claims.session_id}))return respond({error:'Sesión revocada. Vuelve a iniciar sesión.'},401);
 const {member}=await rpc(user.id,'status');
 if(member.status==='BLOQUEADA')return respond({error:'La cuenta está bloqueada'},403);
 if(action==='logout'){await call('/auth/v1/logout?scope=local',undefined,'POST',token);return respond({ok:true});}
 if(action==='change_password'){
 if(String(data.password||'').length<10)throw Error('La nueva contraseña necesita al menos 10 caracteres');
 await call('/auth/v1/user',{password:data.password},'PUT',token);await rpc(user.id,'password_changed',{},key);return respond({ok:true});
 }
 if(action==='admin_reset_password'){
 if(member.role!=='ADMIN'||member.status!=='APROBADA')return respond({error:'Acceso reservado al administrador'},403);
 if(String(data.password||'').length<10)throw Error('La clave temporal necesita al menos 10 caracteres');
 await rpc(user.id,'admin_password_flag',{id:data.id},key);
 await call('/auth/v1/admin/users/'+data.id,{password:data.password},'PUT');return respond({ok:true});
 }
 if(action==='upload'){
 if(member.status!=='APROBADA'||member.force_password)throw Error('Cuenta no habilitada');
 const bytes=Uint8Array.from(atob(data.file||''),c=>c.charCodeAt(0));if(!bytes.length||bytes.length>5242880)throw Error('Usa una imagen JPG o PNG de hasta 5 MB');
 const png=bytes[0]===137&&bytes[1]===80&&bytes[2]===78&&bytes[3]===71&&bytes[4]===13&&bytes[5]===10;
 const jpg=bytes[0]===255&&bytes[1]===216&&bytes[2]===255;if(!png&&!jpg)throw Error('El archivo no es una imagen JPG o PNG válida');
 if(!key||!/^[0-9a-f-]{36}$/i.test(key))throw Error('Identificador de operación inválido');
 const path=`${user.id}/${key}.${png?'png':'jpg'}`;
 const existing=await rpc(user.id,'state');if(existing.receipts.some((r:any)=>r.key===key))return respond({ok:true});
 const uploaded=await fetch(URL+'/storage/v1/object/finance-billy/'+path,{method:'POST',headers:{...headers,'Content-Type':png?'image/png':'image/jpeg','x-upsert':'false'},body:bytes});
 if(!uploaded.ok){const err=await uploaded.json();if(err.statusCode!=='409'&&err.error!=='Duplicate')throw Error('No se pudo guardar la imagen');}
 try{await rpc(user.id,'receipt_create',{...data,file:undefined,path},key);}catch(e){await call('/storage/v1/object/finance-billy',{prefixes:[path]},'DELETE').catch(()=>{});throw e;}
 return respond({ok:true});
 }
 if(action==='receipt_view'){
 const {path}=await rpc(user.id,'receipt_view',{id:data.id});const signed=await call('/storage/v1/object/sign/finance-billy/'+path,{expiresIn:60});return respond({url:URL+'/storage/v1'+(signed.signedURL||signed.signedUrl)});
 }
 if(!actions.has(action))throw Error('Acción no disponible');return respond(await rpc(user.id,action,data,key));
 }catch(e){return respond({error:e instanceof Error?e.message:'Error de operación'},400);}
});
