// Shared filter bar for both pages. Generic and data-driven; all labels come from the caller except the fixed UI strings below.
// o: {bar, chosen, dims:[{k,l,vals(),count(v)}], sel:{k:Set}, flags:[{k,l,get,set}], search:{placeholder,get,set}, body:{get,set}, shown(), clear(), onChange()}
function createFilterBar(o){
  const E=s=>String(s==null?"":s).replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
  const bar=o.bar; bar.classList.add("fb-wrap");
  bar.innerHTML='<div class="fb-row"><span class="fb-dds"></span><span class="fb-flags" style="display:contents"></span><input class="fb-search" type="search"><label class="fb-chk"><input type="checkbox" class="fb-body"> in task body</label><button class="fb-reset" type="button">Reset all</button></div><div class="fb-pop" hidden></div>';
  const dds=bar.querySelector(".fb-dds"), flagsEl=bar.querySelector(".fb-flags"), pop=bar.querySelector(".fb-pop");
  const inp=bar.querySelector(".fb-search"), chk=bar.querySelector(".fb-body"), reset=bar.querySelector(".fb-reset");
  let openK=null;
  inp.placeholder=o.search.placeholder||"Search";
  inp.oninput=()=>{ o.search.set(inp.value); o.onChange(); };
  chk.onchange=()=>{ o.body.set(chk.checked); o.onChange(); };
  reset.onclick=()=>{ o.clear(); inp.value=""; openK=null; o.onChange(); };
  document.addEventListener("click",e=>{ if(openK&&!e.composedPath().includes(bar)){ openK=null; renderDds(); renderPop(); } });
  document.addEventListener("keydown",e=>{ if(e.key==="Escape"&&openK){ openK=null; renderDds(); renderPop(); } });

  function renderDds(){
    dds.innerHTML=o.dims.map(d=>{ const n=o.sel[d.k].size; return `<button type="button" class="fb-dd${n?" on":""}${openK===d.k?" open":""}" data-k="${d.k}">${E(d.l)}<span class="fb-n"${n?"":" style=\"visibility:hidden\""}>: ${n||0}</span> ▾</button>`; }).join("");
    dds.querySelectorAll(".fb-dd").forEach(b=>b.onclick=e=>{ e.stopPropagation(); openK=openK===b.dataset.k?null:b.dataset.k; renderDds(); renderPop(); });
  }
  function renderFlags(){
    flagsEl.innerHTML=(o.flags||[]).map(f=>`<button type="button" class="fb-dd${f.get()?" on":""}" data-flag="${f.k}">⚑ ${E(f.l)}</button>`).join("");
    flagsEl.querySelectorAll(".fb-dd").forEach(b=>b.onclick=()=>{ const f=o.flags.find(x=>x.k===b.dataset.flag); f.set(!f.get()); o.onChange(); });
  }
  function renderPop(){
    if(!openK){ pop.hidden=true; return; }
    const d=o.dims.find(x=>x.k===openK), set=o.sel[d.k];
    pop.hidden=false;
    pop.innerHTML=`<div class="fb-ph"><span>${E(d.l)}</span>${set.size?`<button type="button" class="fb-link" data-clr="1">clear · ${set.size}</button>`:""}</div><div class="fb-chips">`
      +d.vals().map(v=>{ const n=d.count?d.count(v):null; return `<button type="button" class="fb-chip${set.has(v)?" on":""}${n===0?" zero":""}" data-v="${E(v)}">${E(d.lab?d.lab(v):v)}${n==null?"":`<small>${n}</small>`}</button>`; }).join("")+"</div>";
    const b=dds.querySelector(`.fb-dd[data-k="${openK}"]`);
    if(b){ pop.style.top=(b.offsetTop+b.offsetHeight+6)+"px"; pop.style.left=Math.max(0,Math.min(b.offsetLeft,bar.clientWidth-pop.offsetWidth))+"px"; }
    pop.querySelectorAll(".fb-chip").forEach(c=>c.onclick=()=>{ const v=c.dataset.v; set.has(v)?set.delete(v):set.add(v); o.onChange(); });
    const clr=pop.querySelector("[data-clr]"); if(clr) clr.onclick=()=>{ set.clear(); o.onChange(); };
  }
  function renderChosen(){
    const parts=[];
    o.dims.forEach(d=>[...o.sel[d.k]].forEach(v=>parts.push(`<button type="button" class="fb-sel" data-k="${d.k}" data-v="${E(v)}">${E(d.l)}: ${E(d.lab?d.lab(v):v)} ×</button>`)));
    (o.flags||[]).forEach(f=>{ if(f.get()) parts.push(`<button type="button" class="fb-sel" data-flag="${f.k}">⚑ ${E(f.l)} ×</button>`); });
    const q=o.search.get(); if(q) parts.push(`<button type="button" class="fb-sel" data-q="1">🔎 «${E(q)}»${o.body.get()?" in body":""} ×</button>`);
    o.chosen.classList.add("fb-chosen");
    o.chosen.innerHTML=`<span class="fb-count" style="margin:0 6px 0 0">${E(o.shown())}</span>`+(parts.length?"· Selected: ":"")+parts.join("");
    o.chosen.querySelectorAll(".fb-sel").forEach(b=>b.onclick=()=>{
      if(b.dataset.q){ o.search.set(""); inp.value=""; }
      else if(b.dataset.flag){ const f=o.flags.find(x=>x.k===b.dataset.flag); f.set(false); }
      else o.sel[b.dataset.k].delete(b.dataset.v);
      o.onChange();
    });
  }
  return {
    render(){ renderDds(); renderFlags(); renderPop(); renderChosen(); if(inp.value.trim().toLowerCase()!==String(o.search.get()||"").trim().toLowerCase()) inp.value=o.search.get()||""; chk.checked=!!o.body.get(); },
    setSearch(v){ inp.value=v; }
  };
}
