// ===== Общий код обеих страниц: константы, данные, измерения фильтров, шапка, карточка задачи =====
const C=(function(){
  const H=3600e3;
  const ST={"Отменена":"--s-canc","Отклонена":"--s-rej","Заблокирована":"--s-block","В очереди":"--s-ready","В работе":"--s-work","На приёмке":"--s-review","Принята":"--s-done"};
  const ST_ORDER=Object.keys(ST), ORIGINS=["Владелец","Оркестратор","Тестер","Деплоер"], FINAL=new Set(["Принята","Отклонена","Отменена"]);
  const SIZES=["XL","L","M","S","док.","—"];
  const col=s=>`var(${ST[s]||"--s-ready"})`;
  const esc=s=>String(s==null?"":s).replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
  const pad2=n=>String(n).padStart(2,"0");
  const fd=ms=>new Date(ms).toLocaleString("ru-RU",{day:"2-digit",month:"2-digit",hour:"2-digit",minute:"2-digit"});
  const dm=ms=>{const d=new Date(ms);return pad2(d.getDate())+"."+pad2(d.getMonth()+1);};
  const dec=(x,n=1)=>x.toFixed(n).replace(".",",");
  const fh=h=>h<1?Math.round(h*60)+" мин":h<100?dec(h)+" ч":dec(h/24)+" сут";

  // ---- данные: разбор дат, связи, служебные поля ----
  function prep(DATA){
    const tasks=DATA.tasks, byId=Object.fromEntries(tasks.map(t=>[t.id,t]));
    tasks.forEach(t=>{ if(t.c===undefined){ t.c=Date.parse(t.createdAt); t.e=t.endAt?Date.parse(t.endAt):null; t.tl=t.timeline.map(([a,s])=>[Date.parse(a),s]); t.wk=(t.work||[]).map(Date.parse); t.bl=(t.body||"").toLowerCase(); } });
    const edges=DATA.edges.map(e=>({...e,a:e.t0?Date.parse(e.t0):null,b:e.t1?Date.parse(e.t1):null})).filter(e=>byId[e.from]&&byId[e.to]);
    const pings=DATA.pings.map(Date.parse).sort((x,y)=>x-y);
    const NOW=Math.max(Date.parse(DATA.now),pings[pings.length-1]);
    const TC=Math.min(...tasks.map(t=>t.c));
    // служебные поля для фильтров
    const chainN={}; tasks.forEach(t=>chainN[t.chain]=(chainN[t.chain]||0)+1);
    tasks.forEach(t=>{
      const dead=x=>["Отклонена","Отменена"].includes(byId[x].status), tags=[];
      if(edges.some(e=>e.kind==="dep"&&e.to===t.id&&e.b==null&&dead(e.from))) tags.push("зависит от отклонённой или отменённой");
      if(edges.some(e=>e.kind==="dep"&&e.to===t.id&&e.b!=null)) tags.push("была снята зависимость");
      if(edges.some(e=>e.kind==="succ"&&e.from===t.id)) tags.push("заменена преемником");
      if(edges.some(e=>e.kind==="succ"&&e.to===t.id)) tags.push("заменяет предшественника");
      if(t.checkedBy&&t.checkedBy.length) tags.push("проверена тестером");
      if(chainN[t.chain]>1) tags.push("в цепочке переделок");
      if(t.blocks&&t.blocks.length) tags.push("от неё зависят другие");
      t.relTags=tags; t.createdDay=dm(t.c); t.closedDay=t.e?dm(t.e):"не закрыта";
    });
    return {tasks,byId,edges,pings,NOW,TC};
  }
  // активное время по следам коммитов (пауза дольше gapMin не считается)
  function activeModel(pings,gapMin){
    const spans=[]; let a=pings[0], b=a;
    for(const p of pings.slice(1)){ if(p-b<=gapMin*60000) b=p; else { spans.push({a,b}); a=p; b=p; } }
    spans.push({a,b}); let c=0; spans.forEach(s=>{ s.cum=c; c+=(s.b-s.a)/H; }); const total=c;
    return t=>{ for(const s of spans){ if(t<=s.a) return s.cum; if(t<=s.b) return s.cum+(t-s.a)/H; } const l=spans[spans.length-1]; return total+Math.min((t-l.b)/H,gapMin/60); };
  }

  // ---- измерения фильтров: одинаковые на обеих страницах ----
  const sorted=(vals)=>[...new Set(vals)].sort((x,y)=>String(x).localeCompare(String(y),"ru",{numeric:true}));
  const dayKey=s=>{ const m=/^(\d\d)\.(\d\d)$/.exec(s); return m?(+m[2])*100+(+m[1]):9999; };
  function makeDims(tasks,statusOf){
    const one=(k,l,f,vals)=>({k,l,get:t=>[f(t)],vals:vals||(()=>sorted(tasks.map(f)))});
    return [
      one("status","Статус",statusOf,()=>ST_ORDER),
      one("origin","Поставил",t=>t.origin,()=>ORIGINS),
      one("stage","Этап",t=>t.stage),
      one("role","Роль",t=>t.role,()=>["Разработчик","Тестер","Деплоер"]),
      one("tool","Агент",t=>t.tool),
      one("result","Исход выполнения",t=>t.result),
      one("check","Независимая проверка",t=>t.check),
      one("sizeCls","Объём",t=>t.sizeCls,()=>SIZES),
      {k:"rel",l:"Связи",get:t=>t.relTags.length?t.relTags:["без особых связей"],vals:()=>["зависит от отклонённой или отменённой","была снята зависимость","заменена преемником","заменяет предшественника","проверена тестером","в цепочке переделок","от неё зависят другие","без особых связей"]},
      one("created","Создана",t=>t.createdDay,()=>sorted(tasks.map(t=>t.createdDay)).sort((x,y)=>dayKey(x)-dayKey(y))),
      one("closed","Закрыта",t=>t.closedDay,()=>sorted(tasks.map(t=>t.closedDay)).sort((x,y)=>dayKey(x)-dayKey(y)))
    ];
  }
  const matchDims=(t,dims,sel,skip)=>dims.every(d=>d.k===skip||!sel[d.k].size||d.get(t).some(v=>sel[d.k].has(v)));
  const flagMatch=(t,fl)=>(!fl.owner||t.waitsOwner)&&(!fl.blocked||(t.blockedBy.length&&!t.final));

  // ---- шапка и тема ----
  const SUN='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>';
  const MOON='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/></svg>';
  const REFRESH='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-2.6-6.4"/><path d="M21 3v6h-6"/></svg>';
  // Кнопка «Обновить»: просит dashboard/serve.py пересобрать обе страницы (POST rebuild) и перезагружает текущую.
  // Без serve.py (страница открыта как файл) кнопка неактивна: статичный HTML не может запустить Python.
  function initRefresh(btn){
    btn.innerHTML=REFRESH;
    const hint="Пересобрать дашборд целиком (обе страницы) и обновить";
    const noServer="Кнопка работает через сервер: запусти python dashboard/serve.py и открой http://127.0.0.1:8765";
    if(!/^https?:$/.test(location.protocol)){ btn.disabled=true; btn.title=noServer; return; }
    btn.title=hint;
    btn.onclick=async()=>{
      btn.disabled=true; btn.classList.add("busy"); btn.title="Пересборка…";
      try{
        const r=await fetch("rebuild",{method:"POST"});
        const j=await r.json().catch(()=>({}));
        if(r.ok&&j.ok){ location.reload(); return; }
        alert(r.status===404||r.status===501?noServer:"Пересборка не удалась:\n"+(j.error||r.status));
      }catch(e){ alert(noServer); }
      btn.disabled=false; btn.classList.remove("busy"); btn.title=hint;
    };
  }
  function initHeader(active,generated,project){
    let saved=null; try{ saved=localStorage.getItem("dash-theme"); }catch(e){}
    if(saved) document.documentElement.dataset.theme=saved;
    const hdr=document.getElementById("hdr");
    hdr.className="topbar";
    hdr.innerHTML=`<h1>Задачи${project?" · "+esc(project):""}</h1><nav class="nav"><a href="index.html"${active==="over"?' class="on"':""}>Обзор</a><a href="graph.html"${active==="gantt"?' class="on"':""}>Гант и сроки</a></nav><span class="sp"></span><span class="gen">Собрано ${esc(generated)}</span><button class="iconbtn" id="refresh" type="button" aria-label="Пересобрать дашборд"></button><button class="iconbtn" id="theme" type="button" aria-label="Сменить тему"></button>`;
    initRefresh(document.getElementById("refresh"));
    const btn=document.getElementById("theme");
    const isDark=()=>{ const t=document.documentElement.dataset.theme; return t?t==="dark":matchMedia("(prefers-color-scheme:dark)").matches; };
    const paint=()=>{ btn.innerHTML=isDark()?SUN:MOON; btn.title=isDark()?"Светлая тема":"Тёмная тема"; };
    btn.onclick=()=>{ const next=isDark()?"light":"dark"; document.documentElement.dataset.theme=next; try{ localStorage.setItem("dash-theme",next); }catch(e){} paint(); };
    paint();
  }

  // ---- карточка задачи ----
  const rich=s=>esc(s).replace(/^([A-ZА-Я][^:\n]{1,42}:)(?=\s|$)/gm,"<b>$1</b>");
  function sizeShort(t){ const z=t.size; if(!z) return "нет коммитов исполнителя"; return t.sizeCls==="док."?`только документы +${z.add} −${z.del}`:`${t.sizeCls} · код +${z.codeAdd} −${z.codeDel}`; }
  function sizeFull(t){ const z=t.size; if(!z) return '<span style="color:var(--mut)">'+(["Отклонена","Отменена"].includes(t.status)&&t.role==="Разработчик"?"ветка удалена после "+(t.status==="Отменена"?"отмены":"отклонения")+" — объём не восстановить":"нет коммитов исполнителя ([T-NNN] в теме): тестеры, выкладки и документы без кода")+"</span>"; return `<b>${esc(t.sizeCls)}</b> · код: +${z.codeAdd} −${z.codeDel}, ${z.codeFiles} файл(ов)<br><span style="color:var(--mut)">с документами: +${z.add} −${z.del}, ${z.files} файл(ов) · коммитов: ${z.commits}<br>S &lt; 50, M &lt; 300, L &lt; 1000, XL ≥ 1000 строк кода</span>`; }
  function snippet(t,q){ if(!t.bl||!q) return ""; const w=q.toLowerCase().split(/\s+/).filter(Boolean)[0]; if(!w) return ""; const i=t.bl.indexOf(w); if(i<0) return ""; const body=t.body,a=Math.max(0,i-70),b=Math.min(body.length,i+w.length+110); return (a>0?"…":"")+esc(body.slice(a,i))+"<mark>"+esc(body.slice(i,i+w.length))+"</mark>"+esc(body.slice(i+w.length,b))+(b<body.length?"…":""); }
  // ctx: {byId, edges, NOW, dur(a,b), calDur(a,b), actDur(a,b), query, qBody}
  const MUT=s=>`<span style="color:var(--mut)">${s}</span>`;
  function taskCard(t,ctx){
    const link=id=>`<a href="#" data-go="${id}">${id}</a>`;
    const dd=(k,v)=>v?`<dt>${k}</dt><dd>${v}</dd>`:"";
    // исходный текст без пересказа; пустое не показываем
    const fold=(k,summary,txt)=>{ const s=(txt||"").trim(); if(!s) return ""; const n=s.split("\n").length; return `<dt>${k}</dt><dd><details class="fold"><summary>${summary} · ${n} ${n%10===1&&n%100!==11?"строка":(n%10>=2&&n%10<=4&&(n%100<10||n%100>=20)?"строки":"строк")}</summary><pre class="rawtext">${esc(s)}</pre></details></dd>`; };
    const end=t.e!=null?t.e:ctx.NOW;
    const depsIn=ctx.edges.filter(e=>e.kind==="dep"&&e.to===t.id).sort((x,y)=>x.a-y.a);
    const depsOut=ctx.edges.filter(e=>e.kind==="dep"&&e.from===t.id);
    const succTo=ctx.edges.filter(e=>e.kind==="succ"&&e.from===t.id).map(e=>e.to), succFrom=ctx.edges.filter(e=>e.kind==="succ"&&e.to===t.id).map(e=>e.from);
    const checksOf=ctx.edges.filter(e=>e.kind==="check"&&e.from===t.id).map(e=>e.to);
    const hist=t.tl.map(([a,s],i)=>`<li><span class="tag" style="background:${col(s)}">${s}</span> ${fd(a)}${t.tl[i+1]?" · "+fh(ctx.dur(a,t.tl[i+1][0]))+" в этом статусе":""}</li>`).join("");
    const deadNow=x=>["Отклонена","Отменена"].includes(ctx.byId[x].status);
    // три разные сущности: статус реестра / исход выполнения / независимая проверка
    const outcome=t.outcomeSrc
      ? `${esc(t.result)} ${MUT(`(в отчёте исполнителя — ${t.outcomeSrc}: ${esc(t.outcomeRaw)})`)}`+(t.result==="Завершено исполнителем"?"<br>"+MUT("Исполнитель сообщил о завершении работы. Это не приёмка: решение отражено в статусе реестра."):"")
      : MUT("нет отчёта исполнителя (раздел Result пуст)");
    let verify="";
    if(t.role==="Разработчик"){
      const list=(t.checkedBy||[]).map(([id,v,s])=>`${link(id)} — ${v||"без вердикта"} ${MUT("(задача проверки: "+s+")")}`);
      verify=esc(t.check)+(list.length?"<br>"+list.join("<br>"):"");
    } else if(t.verdict||checksOf.length){
      verify=`Эта задача — проверка${checksOf.length?" "+checksOf.map(link).join(", "):""}${t.verdict?`; вердикт: <b>${esc(t.verdict)}</b>`:""}`;
    }
    const rc=t.reportCommit;
    return `<div class="tcard"><h2>Задача ${t.id}${t.sizeCls&&t.sizeCls!=="—"?`<span class="tag sz" title="${esc(sizeShort(t))}">${esc(t.sizeCls)}</span>`:""}</h2><dl>
      ${dd("Название",esc(t.title))}
      ${ctx.query&&ctx.qBody?dd("Найдено в тексте",snippet(t,ctx.query)):""}
      ${dd("Этап · роль · агент",esc(t.stage+" · "+t.role+" · "+t.tool))}
      ${dd("Поставил",esc(t.origin)+" "+MUT(`— ${esc(t.originWhy)} (оценка)`))}
      ${dd("Статус в реестре",`<span class="tag" style="background:${col(t.status)}">${t.status}</span>`)}
      ${dd("Исход выполнения",outcome)}
      ${dd("Независимая проверка",verify)}
      ${dd("Срок",`создана ${fd(t.c)} → ${t.e!=null?"закрыта "+fd(t.e):"не закрыта"}; календарно ${fh(ctx.calDur(t.c,end))}, активно ${fh(ctx.actDur(t.c,end))}`)}
      ${fold("Полное задание","Goal",t.goalFull)}
      ${fold("Отчёт исполнителя","Result",t.resultFull)}
      ${fold("Заметки","Notes",t.notes)}
      ${dd("Зависит от",depsIn.map(e=>`${link(e.from)} ${MUT(`(${ctx.byId[e.from].status}${deadNow(e.from)?", не действует":""}) — с ${fd(e.a)}${e.b!=null?" по "+fd(e.b)+" · связь снята":""}`)}`).join("<br>"))}
      ${dd("От неё зависят",depsOut.map(e=>link(e.to)+(e.b!=null?" "+MUT("(снята)"):"")).join(", "))}
      ${dd("Заменяет",succFrom.map(link).join(", "))}
      ${dd("Заменена на",succTo.length?succTo.map(link).join(", "):(["Отклонена","Отменена"].includes(t.status)?MUT("в реестре не указан"):""))}
      ${dd("История статусов","<ul>"+hist+"</ul>")}
      ${dd("Коммит / артефакт в реестре",esc(t.commit))}
      ${rc?dd("Коммит, указанный исполнителем в отчёте",`<code>${esc(rc.sha)}</code> ${MUT(`(строка «${esc(rc.label)}» отчёта: ${esc(rc.line)}) · не означает, что коммит принят в main`)}`):""}
      ${dd("Объём изменений",sizeFull(t))}
      ${t.file?dd("Файл",`<a href="../${t.file}">${t.file}</a>`):""}
    </dl></div>`;
  }
  function bindCard(root,onGo){
    root.querySelectorAll("a[data-go]").forEach(a=>a.onclick=e=>{ e.preventDefault(); onGo(a.dataset.go); });
  }
  return {H,ST,ST_ORDER,ORIGINS,FINAL,SIZES,col,esc,fd,dm,dec,fh,prep,activeModel,makeDims,matchDims,flagMatch,initHeader,taskCard,bindCard,snippet,sizeShort,sizeFull};
})();
