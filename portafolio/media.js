
(function(){
'use strict';
const ENDPOINT='https://ulylpdeutafjuuevdllz.supabase.co/functions/v1/portfolio-media';
const FINANCE='https://ulylpdeutafjuuevdllz.supabase.co/functions/v1/finance-api';
const KEY='sb_publishable_rygFKvTzyxTvn9SfTHcYdA_tEeS6OTH';
const byId=id=>document.getElementById(id);
const gallery=document.querySelector('#bm-detail .bm-gallery'),galleryTemplate=gallery.innerHTML;
const cards=Array.from(document.querySelectorAll('.bm-app'));
let media=[],adminMedia=[],session=null,busy=false;
const originalIcons=new Map(cards.map(card=>[card.getAttribute('href').split('/').pop(),card.querySelector('.bm-icon').innerHTML]));
const uploaded=new WeakSet();
try{session=JSON.parse(sessionStorage.getItem('bm-admin-session')||'null');}catch(_){}
function save(){try{if(session)sessionStorage.setItem('bm-admin-session',JSON.stringify(session));else sessionStorage.removeItem('bm-admin-session');}catch(_){}}
function image(target,url,alt){const img=document.createElement('img');img.src=url;img.alt=alt;img.loading='lazy';img.decoding='async';target.replaceChildren(img);}
function newest(list){return list.slice().sort((a,b)=>a.created_at.localeCompare(b.created_at)).pop();}
function render(slug){
 const rows=media.filter(x=>x.app_slug===slug);
 gallery.innerHTML=galleryTemplate;
 const shots=rows.filter(x=>x.kind==='screenshot');
 if(shots.length){gallery.replaceChildren();shots.forEach((item,i)=>{const frame=document.createElement('div');frame.className='bm-shot bm-scroll-shot';frame.tabIndex=0;frame.setAttribute('role','region');frame.setAttribute('aria-label',(item.caption||'Captura '+(i+1))+'. Desplázate hacia abajo para verla completa.');image(frame,item.url,item.caption||'Captura '+(i+1));gallery.append(frame);});}
 gallery.scrollLeft=0;gallery.tabIndex=0;
 const logo=newest(rows.filter(x=>x.kind==='logo'));
 if(logo)image(byId('bm-detail-icon'),logo.url,'Logotipo de la aplicación');else byId('bm-detail-icon').innerHTML=originalIcons.get(slug)||'';
 const actions=document.querySelector('#bm-detail .bm-actions');actions.querySelector('[data-cloud-apk]')?.remove();
 const bundledApk=actions.querySelector('[data-bundled-apk]');
 const previousCuadrosApk='quadro-app/apk/1d62496e-b026-4525-9887-65cd05554591.apk';
 const apk=newest(rows.filter(x=>x.kind==='apk'&&(!bundledApk||x.object_path!==previousCuadrosApk)));
 if(bundledApk)bundledApk.hidden=!!apk;
 if(!apk){if(!bundledApk&&!Array.from(actions.querySelectorAll('button')).some(b=>b.textContent.includes('APK'))){const pending=document.createElement('button');pending.type='button';pending.disabled=true;pending.className='bm-secondary';pending.textContent='APK · próximamente';actions.append(pending);}if(slug==='finance-billy'){const note=document.querySelector('#bm-detail .bm-detail-note');if(note)note.textContent='Puedes abrir la web y solicitar una cuenta. El acceso a las funciones requiere aprobación del administrador.';}}
 if(apk){actions.querySelectorAll('button').forEach(b=>{if(b.textContent.includes('APK'))b.remove();});
 const link=document.createElement('a');link.href=apk.url+'?download='+encodeURIComponent(slug+'.apk');link.className='bm-secondary';link.textContent='Descargar APK';link.setAttribute('download',slug+'.apk');link.dataset.cloudApk='true';actions.append(link);
 if(slug==='finance-billy'){const note=document.querySelector('#bm-detail .bm-detail-note');if(note)note.textContent='Puedes abrir la web y descargar el APK. El acceso a las funciones requiere una cuenta aprobada por el administrador.';}}
}
function canonicalSlug(slug){return slug==='quadro-app'?'cuadros-app':slug;}
function normalizeMedia(rows){return rows.map(row=>({...row,app_slug:canonicalSlug(row.app_slug)}));}
function current(){const hash=location.hash;return hash.startsWith('#app/')?canonicalSlug(hash.slice(5)):null;}
window.BMPortfolioMedia={render};
async function load(){
 const response=await fetch(ENDPOINT,{cache:'no-store'});const data=await response.json();if(!response.ok||!Array.isArray(data.media))throw Error('No se pudieron cargar los archivos');
 media=normalizeMedia(data.media);
 cards.forEach(card=>{const slug=card.getAttribute('href').split('/').pop(),logo=newest(media.filter(x=>x.app_slug===slug&&x.kind==='logo'));if(logo)image(card.querySelector('.bm-icon'),logo.url,'Logotipo de la aplicación');else card.querySelector('.bm-icon').innerHTML=originalIcons.get(slug)||'';});
 if(current())render(current());
 if(session)await refreshAdmin();
}
const info=byId('bm-upload-status');
function status(text){info.textContent=text;}
function controls(){byId('bm-admin-login').hidden=!!session;byId('bm-admin-upload').hidden=!session;byId('bm-media-manager').hidden=!session;if(!session){adminMedia=[];byId('bm-media-list').replaceChildren();}}
async function finance(action,data={},token){
 const response=await fetch(FINANCE,{method:'POST',headers:{apikey:KEY,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify({action,data})});const result=await response.json();if(!response.ok)throw Error(result.error||'No se pudo iniciar sesión');return result;
}
async function token(){
 if(!session)throw Error('Inicia sesión');
 if(session.expires_at*1000<Date.now()+60000){session=await finance('refresh',{refresh_token:session.refresh_token});save();}
 return session.access_token;
}
byId('bm-admin-login').addEventListener('submit',async event=>{
 event.preventDefault();const button=event.currentTarget.querySelector('button');button.disabled=true;status('Comprobando acceso…');
 try{const next=await finance('login',{cedula:byId('bm-admin-id').value,password:byId('bm-admin-password').value});
 const state=await finance('status',{},next.access_token);
 if(state.member?.role!=='ADMIN'||state.member?.status!=='APROBADA'||state.member?.force_password){await finance('logout',{},next.access_token).catch(()=>{});throw Error('Usa una cuenta de administrador aprobada con su contraseña actual.');}
 session=next;save();controls();await refreshAdmin();status('Acceso autorizado. Puedes subir archivos o eliminar los anteriores.');
 }catch(error){status(error.message);}finally{button.disabled=false;byId('bm-admin-password').value='';}
});
const selector=byId('bm-upload-app');
cards.forEach(card=>{const option=document.createElement('option');option.value=card.getAttribute('href').split('/').pop();option.textContent=card.querySelector('h3').textContent;selector.append(option);});

async function management(action,id){
 const response=await fetch(ENDPOINT,{method:'POST',headers:{Authorization:'Bearer '+await token(),'Content-Type':'application/json'},body:JSON.stringify({action,...(id?{id}:{})})});
 const data=await response.json();if(!response.ok)throw Error(data.error||'No se pudo actualizar la lista');return data;
}
async function refreshAdmin(){const data=await management('admin-list');adminMedia=normalizeMedia(data.media);renderAdmin();}
function renderAdmin(){
 const list=byId('bm-media-list');list.replaceChildren();
 const files=adminMedia.filter(item=>item.app_slug===selector.value);
 if(!files.length){const empty=document.createElement('p');empty.textContent='Esta aplicación todavía no tiene archivos subidos.';list.append(empty);return;}
 files.forEach((item,i)=>{
 const row=document.createElement('article');row.className='bm-managed-file';
 if(item.kind!=='apk'){const thumb=document.createElement('img');thumb.src=item.url;thumb.alt=item.caption||'Vista previa';thumb.loading='lazy';row.append(thumb);}
 const content=document.createElement('div');const name=document.createElement('strong');name.textContent=item.caption||({screenshot:'Captura',logo:'Logotipo',apk:'APK'}[item.kind]+' '+(i+1));
 const state=document.createElement('p');state.textContent=item.deleted_at?'Retirado del catálogo':'Publicado';
 const button=document.createElement('button');button.type='button';button.className='bm-secondary';button.textContent=item.deleted_at?'Restaurar':'Eliminar';
 button.addEventListener('click',async()=>{
 if(busy)return;busy=true;button.disabled=true;
 try{await management(item.deleted_at?'restore':'remove',item.id);await load();status(item.deleted_at?'Archivo restaurado.':'Archivo retirado del catálogo. Puedes restaurarlo o subir uno nuevo.');}
 catch(error){status(error.message);}finally{busy=false;button.disabled=false;}
 });
 content.append(name,state,button);row.append(content);list.append(row);
 });
}
selector.addEventListener('change',renderAdmin);
byId('bm-upload-kind').addEventListener('change',function(){
 const input=byId('bm-upload-files');input.value='';input.multiple=this.value==='screenshot';input.accept=this.value==='apk'?'.apk':'image/jpeg,image/png,image/webp';
});
byId('bm-admin-logout').addEventListener('click',async()=>{if(busy)return;const old=session;session=null;save();controls();status('Sesión cerrada.');if(old)finance('logout',{},old.access_token).catch(()=>{});});
byId('bm-admin-upload').addEventListener('submit',async event=>{
 event.preventDefault();if(busy)return;
 const files=Array.from(byId('bm-upload-files').files),slug=selector.value,kind=byId('bm-upload-kind').value;
 if(!files.length){status('Selecciona al menos un archivo.');return;}
 if(files.some(file=>file.size>41943040)){status('Cada archivo debe pesar 40 MB o menos.');return;}
 busy=true;const submit=event.currentTarget.querySelector('[type=submit]');submit.disabled=true;byId('bm-admin-logout').disabled=true;
 let count=0;const offset=media.filter(x=>x.app_slug===slug&&x.kind===kind).reduce((max,x)=>Math.max(max,x.sort_order+1),0);
 try{
 for(let i=0;i<files.length;i++){
 const file=files[i];if(uploaded.has(file)){count++;continue;}
 status('Subiendo '+(i+1)+' de '+files.length+': '+file.name);
 const form=new FormData();form.append('file',file);form.append('slug',slug);form.append('kind',kind);form.append('caption',byId('bm-upload-caption').value);form.append('position',String(offset+i));
 const response=await fetch(ENDPOINT,{method:'POST',headers:{Authorization:'Bearer '+await token()},body:form});const result=await response.json();
 if(!response.ok)throw Error(result.error||'No se pudo subir el archivo');
 uploaded.add(file);count++;
 }
 await load();byId('bm-upload-files').value='';status(count+' archivo(s) publicado(s). Ya están disponibles para los visitantes.');
 }catch(error){status(count+' archivo(s) completado(s). '+error.message+' Puedes reintentar los pendientes.');await load().catch(()=>{});}
 finally{busy=false;submit.disabled=false;byId('bm-admin-logout').disabled=false;}
});
controls();load().catch(()=>{const note=byId('bm-cloud-status');note.hidden=false;note.textContent='No se pudieron cargar los archivos del catálogo. Recarga la página para reintentar.';});
})();
