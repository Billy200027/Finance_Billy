
(function () {
  'use strict';
  const endpoint='https://ulylpdeutafjuuevdllz.supabase.co/functions/v1/portfolio-media';
  const form=document.getElementById('bm-idea-form');
  const field=document.getElementById('bm-idea-text');
  const status=document.getElementById('bm-ideas-status');
  const list=document.getElementById('bm-ideas-list');
  const more=document.getElementById('bm-ideas-more');
  const date=new Intl.DateTimeFormat('es-EC',{dateStyle:'medium',timeZone:'America/Guayaquil'});
  let browser=crypto.randomUUID();
  try {
    const saved=localStorage.getItem('bm-ideas-browser');
    if(saved&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(saved))browser=saved;
    else localStorage.setItem('bm-ideas-browser',browser);
  } catch {}
  let before=null;
  let revision=0;
  let pending=null;

  async function request(action,fields={},token) {
    const response=await fetch(endpoint,{
      method:'POST',
      headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},
      body:JSON.stringify({action,browser,...fields})
    });
    const result=await response.json();
    if(!response.ok)throw Error(result.error||'No se pudo completar la operación.');
    return result;
  }

  function render(idea) {
    const card=document.createElement('article');
    card.className='bm-idea';
    const body=document.createElement('p');
    body.className='bm-idea-text';
    body.textContent=idea.body;
    const time=document.createElement('small');
    time.textContent=date.format(new Date(idea.created_at));
    const actions=document.createElement('div');
    actions.className='bm-idea-actions';
    const vote=document.createElement('button');
    vote.type='button';
    vote.className='bm-secondary';
    function setVote(result) {
      vote.setAttribute('aria-pressed',String(result.liked));
      vote.textContent='Me gusta · '+result.likes;
    }
    setVote(idea);
    vote.addEventListener('click',async()=>{
      vote.disabled=true;
      status.textContent='';
      try { setVote(await request('ideas-vote',{id:idea.id,liked:vote.getAttribute('aria-pressed')!=='true'})); }
      catch(error){ status.textContent=error.message; }
      finally { vote.disabled=false; }
    });
    actions.append(vote);
    if(window.BMPortfolioMedia?.isAdmin()){
      const remove=document.createElement('button');
      remove.type='button';
      remove.className='bm-secondary';
      remove.textContent='Retirar idea';
      remove.addEventListener('click',async()=>{
        if(!window.confirm('¿Retirar esta idea del portafolio?'))return;
        remove.disabled=true;
        try {
          await request('ideas-hide',{id:idea.id},await window.BMPortfolioMedia.adminToken());
          await load(true);
          status.textContent='Idea retirada.';
        } catch(error) { status.textContent=error.message; }
        finally { remove.disabled=false; }
      });
      actions.append(remove);
    }
    card.append(body,time,actions);
    list.append(card);
  }

  async function load(reset) {
    const current=++revision;
    more.disabled=true;
    try {
      const result=await request('ideas-list',{before:reset?null:before});
      if(current!==revision)return;
      const ideas=result.ideas.slice(0,20);
      if(reset)list.replaceChildren();
      if(reset&&!ideas.length)list.textContent='Todavía no hay ideas publicadas. Comparte la primera.';
      ideas.forEach(render);
      before=ideas.at(-1)?.id??null;
      more.hidden=result.ideas.length<=20;
    } catch(error) {
      if(current===revision)status.textContent=error.message;
    } finally {
      if(current===revision)more.disabled=false;
    }
  }

  form.addEventListener('submit',async event=>{
    event.preventDefault();
    const body=field.value.trim();
    if(!body){status.textContent='Escribe tu idea antes de publicarla.';return;}
    if(pending?.body!==body)pending={body,request:crypto.randomUUID()};
    const button=form.querySelector('button');
    button.disabled=true;
    field.disabled=true;
    status.textContent='Publicando…';
    try {
      await request('ideas-publish',pending);
      pending=null;
      field.value='';
      status.textContent='Tu idea se publicó.';
      await load(true);
    } catch(error){status.textContent=error.message;}
    finally{button.disabled=false;field.disabled=false;}
  });
  more.addEventListener('click',()=>load(false));
  function openIdeas(){
    if(location.hash==='#ideas')load(true);
  }
  window.addEventListener('hashchange',openIdeas);
  openIdeas();
})();
