import { db, tem } from '../app.js';
import { EMPRESA } from '../config.js';
import { h, num, moeda, chip, modal, chamar, ler, cadastros, toast, msgErro, formModal, ops, contem, confirmar, imprimirHtml, limparCache } from '../util.js';

let produtoId = null;
let busca = '';

export async function render(el) {
  if (produtoId) return detalhe(el);
  const lista = (await ler(db.from('v_custo_produto').select('*').order('produto'))).filter(p => contem(p, ['produto', 'codigo'], busca));
  el.innerHTML = `
    <div class="cab"><div><h1>Ficha Técnica</h1><p>Roteiro de operações com tempo padrão, consumo de matéria-prima, medidas e custo por produto.</p></div></div>
    <div class="filtros"><label class="campo">Buscar<input id="busca" value="${h(busca)}" placeholder="Produto ou código…"></label></div>
    <div class="tabela-wrap"><table><thead><tr><th>Código</th><th>Produto</th><th class="n">Operações</th><th class="n">Tempo/peça</th><th class="n">Itens MP</th><th class="n">Custo MP</th><th class="n">R$ facção</th><th class="n">Preço</th><th></th></tr></thead>
    <tbody>${lista.map(p => `<tr><td>${h(p.codigo || '')}</td><td class="forte">${h(p.produto)}</td><td class="n">${p.operacoes || '—'}</td><td class="n">${p.tempo_seg ? `${num(p.tempo_seg / 60, 1)} min` : '—'}</td>
      <td class="n">${p.itens_mp || '—'}</td><td class="n">${p.itens_mp ? moeda(p.custo_mp) : '—'}</td><td class="n">${p.valor_faccao != null ? moeda(p.valor_faccao) : '—'}</td><td class="n">${p.preco != null ? moeda(p.preco) : '—'}</td>
      <td><button class="btn peq" data-p="${p.produto_id}">Abrir</button></td></tr>`).join('')}</tbody></table></div>`;
  el.querySelector('#busca').onchange = (e) => { busca = e.target.value; render(el); };
  el.querySelectorAll('[data-p]').forEach(b => b.onclick = () => { produtoId = +b.dataset.p; render(el); });
}

async function detalhe(el) {
  const pode = tem('cadastros');
  const cad = await cadastros(db);
  const [[custo], fichaArr, roteiro, ft, medidas, mps] = await Promise.all([
    ler(db.from('v_custo_produto').select('*').eq('produto_id', produtoId)),
    ler(db.from('fichas_produto').select('*').eq('produto_id', produtoId)),
    ler(db.from('produto_processos').select('*, processos(nome)').eq('produto_id', produtoId).order('sequencia')),
    ler(db.from('ficha_tecnica').select('*, materias_primas(nome, unidade, valor)').eq('produto_id', produtoId)),
    ler(db.from('ficha_medidas').select('*').eq('produto_id', produtoId).order('ordem').order('id')),
    ler(db.from('materias_primas').select('*').eq('ativo', true).order('nome')),
  ]);
  const prod = cad.produtos.find(p => p.id === produtoId);
  const fp = fichaArr[0] || {};
  const tams = cad.tamanhos.filter(t => t.ativo).map(t => t.nome);
  el.innerHTML = `
    <div class="cab"><div><button class="btn peq" id="voltar">← Produtos</button><h1 style="margin-top:8px">${h(prod.nome)}</h1>
      <p>${prod.codigo ? `Código ${h(prod.codigo)} · ` : ''}${prod.estamparia_apos ? chip('Estampa após produção', 'acento') : ''}</p></div>
      <button class="btn" id="imprimir">🖨 Imprimir ficha</button></div>
    <div class="grade g4">
      <div class="kpi"><div class="rot">Custo matéria-prima</div><div class="val">${moeda(custo.custo_mp)}</div></div>
      <div class="kpi"><div class="rot">Tempo por peça</div><div class="val">${num(custo.tempo_seg / 60, 1)} min</div></div>
      <div class="kpi"><div class="rot">Valor facção</div><div class="val">${prod.valor_faccao != null ? moeda(prod.valor_faccao) : '—'}</div></div>
      <div class="kpi"><div class="rot">Custo total (MP + facção)</div><div class="val">${moeda(Number(custo.custo_mp) + Number(prod.valor_faccao || 0))}</div></div>
    </div>

    <div class="card" style="margin-top:14px"><div class="linha1"><h2>Ficha do produto</h2>${pode ? '<button class="btn peq" id="ed-ficha">Editar</button>' : ''}</div>
      <div class="grade g3 peq">
        <div><b>Referência:</b> ${h(fp.referencia || '—')}</div><div><b>Criação:</b> ${h(fp.criacao || '—')}</div><div><b>Pilotagem:</b> ${h(fp.pilotagem || '—')}</div>
        <div><b>Grade:</b> ${h(fp.grade || '—')}</div><div style="grid-column:span 2"><b>Informação de corte:</b> ${h(fp.info_corte || '—')}</div>
        ${fp.obs ? `<div style="grid-column:1/-1"><b>Obs.:</b> ${h(fp.obs)}</div>` : ''}
      </div>
      ${fp.foto_frente || fp.foto_costas ? `<div class="acoes" style="margin-top:10px">${[fp.foto_frente, fp.foto_costas].filter(Boolean).map(u => `<a href="${h(u)}" target="_blank" rel="noopener"><img src="${h(u)}" alt="" style="max-height:160px;border-radius:8px;border:1px solid var(--linha)"></a>`).join('')}</div>` : ''}
    </div>

    <div class="card" style="margin-top:14px"><div class="linha1"><h2>Roteiro de operações</h2>${pode ? '<button class="btn peq" id="ed-rot">Editar roteiro</button>' : ''}</div>
      <div class="tabela-wrap"><table><thead><tr><th>#</th><th>Operação</th><th class="n">Tempo (s)</th></tr></thead>
      <tbody>${roteiro.map(r => `<tr><td>${r.sequencia}</td><td>${h(r.processos?.nome)}</td><td class="n">${num(r.tempo_seg)}</td></tr>`).join('') || '<tr><td colspan="3" class="vazio">Sem roteiro.</td></tr>'}</tbody>
      <tfoot><tr class="grupo"><td colspan="2">Total</td><td class="n">${num(custo.tempo_seg)} s</td></tr></tfoot></table></div></div>

    <div class="card" style="margin-top:14px"><div class="linha1"><h2>Consumo de matéria-prima</h2>${pode ? '<button class="btn peq" id="add-mp">+ Matéria-prima</button>' : ''}</div>
      <div class="tabela-wrap"><table><thead><tr><th>Matéria-prima</th><th>Unid.</th><th class="n">Consumo/peça</th><th class="n">Valor unit.</th><th class="n">Custo</th><th></th></tr></thead>
      <tbody>${ft.map(x => `<tr><td>${h(x.materias_primas.nome)}</td><td>${h(x.materias_primas.unidade)}</td><td class="n">${num(x.consumo, 3)}</td><td class="n">${moeda(x.materias_primas.valor)}</td>
        <td class="n forte">${moeda(x.consumo * x.materias_primas.valor)}</td><td>${pode ? `<div class="acoes"><button class="btn peq" data-edmp="${x.id}">Editar</button><button class="btn peq perigo" data-delmp="${x.id}">🗑</button></div>` : ''}</td></tr>`).join('') || '<tr><td colspan="6" class="vazio">Sem itens.</td></tr>'}</tbody></table></div></div>

    <div class="card" style="margin-top:14px"><div class="linha1"><h2>Tabela de medidas (cm)</h2>${pode ? '<button class="btn peq" id="add-med">+ Medida</button>' : ''}</div>
      <div class="tabela-wrap"><table><thead><tr><th>Descrição</th>${tams.map(t => `<th class="n">${h(t)}</th>`).join('')}<th></th></tr></thead>
      <tbody>${medidas.map(m => `<tr><td>${h(m.descricao)}</td>${tams.map(t => `<td class="n">${h(m.medidas?.[t] ?? '')}</td>`).join('')}
        <td>${pode ? `<div class="acoes"><button class="btn peq" data-edmed="${m.id}">Editar</button><button class="btn peq perigo" data-delmed="${m.id}">🗑</button></div>` : ''}</td></tr>`).join('') || `<tr><td colspan="${tams.length + 2}" class="vazio">Sem medidas.</td></tr>`}</tbody></table></div></div>`;

  const re = () => render(el);
  el.querySelector('#voltar').onclick = () => { produtoId = null; render(el); };
  el.querySelector('#imprimir').onclick = () => imprimirFicha(prod, fp, roteiro, ft, medidas, tams, custo);
  el.querySelector('#ed-ficha')?.addEventListener('click', async () => {
    const v = await formModal({ titulo: 'Ficha do produto', largo: true, campos: [
      { k: 'referencia', r: 'Referência', valor: fp.referencia }, { k: 'criacao', r: 'Criação', valor: fp.criacao }, { k: 'pilotagem', r: 'Pilotagem', valor: fp.pilotagem },
      { k: 'grade', r: 'Grade', valor: fp.grade }, { k: 'foto_frente', r: 'Link da foto (frente)', valor: fp.foto_frente }, { k: 'foto_costas', r: 'Link da foto (costas)', valor: fp.foto_costas },
      { k: 'info_corte', r: 'Informação de corte', tipo: 'textarea', valor: fp.info_corte }, { k: 'obs', r: 'Observações', tipo: 'textarea', valor: fp.obs }] });
    if (!v) return;
    const { error } = await db.from('fichas_produto').upsert({ produto_id: produtoId, ...v, atualizado_em: new Date().toISOString() });
    if (error) return toast(msgErro(error), 'erro');
    toast('Ficha salva.', 'ok'); re();
  });
  el.querySelector('#ed-rot')?.addEventListener('click', () => editarRoteiro(cad, roteiro, re));
  const formMp = async (x) => {
    const v = await formModal({ titulo: x ? 'Editar consumo' : 'Adicionar matéria-prima', campos: [
      { k: 'mp', r: 'Matéria-prima', tipo: 'select', opcoes: mps.map(m => [m.id, `${m.nome} (${m.unidade} · ${moeda(m.valor)})`]), valor: x?.materia_prima_id, req: true },
      { k: 'consumo', r: 'Consumo por peça', tipo: 'number', min: 0.0001, valor: x?.consumo, req: true }, { k: 'obs', r: 'Observação', valor: x?.obs }] });
    if (!v) return;
    const dados = { produto_id: produtoId, materia_prima_id: +v.mp, consumo: v.consumo, obs: v.obs };
    const { error } = x ? await db.from('ficha_tecnica').update(dados).eq('id', x.id) : await db.from('ficha_tecnica').insert(dados);
    if (error) return toast(msgErro(error), 'erro');
    toast('Salvo.', 'ok'); re();
  };
  el.querySelector('#add-mp')?.addEventListener('click', () => formMp(null));
  el.querySelectorAll('[data-edmp]').forEach(b => b.onclick = () => formMp(ft.find(x => String(x.id) === b.dataset.edmp)));
  el.querySelectorAll('[data-delmp]').forEach(b => b.onclick = async () => {
    if (!await confirmar('Remover', 'Remover esta matéria-prima da ficha?', 'Remover', 'perigo')) return;
    const { error } = await db.from('ficha_tecnica').delete().eq('id', +b.dataset.delmp);
    if (error) return toast(msgErro(error), 'erro'); re();
  });
  const formMed = async (m) => {
    const v = await formModal({ titulo: m ? 'Editar medida' : 'Nova medida', campos: [{ k: 'descricao', r: 'Descrição', valor: m?.descricao, req: true },
      ...tams.map(t => ({ k: 't_' + t, r: t, valor: m?.medidas?.[t] })), { k: 'ordem', r: 'Ordem', tipo: 'number', valor: m?.ordem ?? medidas.length + 1 }] });
    if (!v) return;
    const med = {}; tams.forEach(t => { if (v['t_' + t]) med[t] = v['t_' + t]; });
    const dados = { produto_id: produtoId, descricao: v.descricao, medidas: med, ordem: v.ordem || 0 };
    const { error } = m ? await db.from('ficha_medidas').update(dados).eq('id', m.id) : await db.from('ficha_medidas').insert(dados);
    if (error) return toast(msgErro(error), 'erro');
    toast('Salvo.', 'ok'); re();
  };
  el.querySelector('#add-med')?.addEventListener('click', () => formMed(null));
  el.querySelectorAll('[data-edmed]').forEach(b => b.onclick = () => formMed(medidas.find(x => String(x.id) === b.dataset.edmed)));
  el.querySelectorAll('[data-delmed]').forEach(b => b.onclick = async () => {
    if (!await confirmar('Remover', 'Remover esta medida?', 'Remover', 'perigo')) return;
    const { error } = await db.from('ficha_medidas').delete().eq('id', +b.dataset.delmed);
    if (error) return toast(msgErro(error), 'erro'); re();
  });
}

function linhaRot(cad, r = {}) {
  return `<tr><td><button type="button" class="btn peq" data-up>↑</button><button type="button" class="btn peq" data-down>↓</button></td>
    <td><input class="inp" list="lista-proc" data-c="proc" value="${h(r.processos?.nome || r.nome || '')}" style="width:100%;min-width:260px"></td>
    <td><input class="inp num" type="number" min="0" step="any" data-c="tempo" value="${h(r.tempo_seg ?? '')}"></td>
    <td><button type="button" class="btn peq perigo" data-rm>×</button></td></tr>`;
}

function editarRoteiro(cad, roteiro, depois) {
  modal({
    titulo: 'Roteiro de operações', largo: true,
    corpo: `<p class="muted">Digite o nome da operação (escolha da lista ou crie uma nova) e o tempo padrão em <b>segundos por peça</b>. A ordem das linhas é a sequência.</p>
      <datalist id="lista-proc">${cad.processos.filter(p => p.ativo).map(p => `<option value="${h(p.nome)}">`).join('')}</datalist>
      <div class="tabela-wrap"><table><thead><tr><th></th><th>Operação</th><th>Tempo (s)</th><th></th></tr></thead><tbody id="rot">${(roteiro.length ? roteiro : [{}]).map(r => linhaRot(cad, r)).join('')}</tbody></table></div>
      <button type="button" class="btn peq" id="add" style="margin-top:8px">+ Operação</button> <span class="forte" id="tot" style="margin-left:10px"></span>`,
    aoAbrir: (m) => {
      const tb = m.querySelector('#rot');
      const tot = () => { const s = [...tb.querySelectorAll('[data-c=tempo]')].reduce((a, i) => a + (+i.value || 0), 0); m.querySelector('#tot').textContent = `Total: ${num(s)} s (${num(s / 60, 1)} min)`; };
      m.addEventListener('input', tot); tot();
      m.querySelector('#add').onclick = () => tb.insertAdjacentHTML('beforeend', linhaRot(cad));
      m.addEventListener('click', (e) => {
        const tr = e.target.closest('tr');
        if (e.target.matches('[data-rm]') && tb.children.length > 1) { tr.remove(); tot(); }
        if (e.target.matches('[data-up]') && tr.previousElementSibling) tr.parentNode.insertBefore(tr, tr.previousElementSibling);
        if (e.target.matches('[data-down]') && tr.nextElementSibling) tr.parentNode.insertBefore(tr.nextElementSibling, tr);
      });
    },
    botoes: [{ texto: 'Cancelar' }, { texto: 'Salvar roteiro', classe: 'pri', acao: async (m) => {
      const itens = [...m.querySelectorAll('#rot tr')].map(tr => ({ processo: tr.querySelector('[data-c=proc]').value.trim(), tempo_seg: tr.querySelector('[data-c=tempo]').value })).filter(i => i.processo);
      const nomes = itens.map(i => i.processo.toUpperCase());
      if (new Set(nomes).size !== nomes.length) { toast('Há operações repetidas.', 'erro'); return false; }
      const porNome = new Map(cad.processos.map(p => [p.nome.toUpperCase(), p.id]));
      const r = await chamar(db, 'salvar_roteiro', { p_produto_id: produtoId, p_itens: itens.map(i => ({ processo_id: porNome.get(i.processo.toUpperCase()) || null, processo: i.processo, tempo_seg: i.tempo_seg === '' ? 0 : +i.tempo_seg })) });
      if (!r) return false;
      limparCache(); toast('Roteiro salvo.', 'ok'); depois();
    } }]
  });
}

function imprimirFicha(prod, fp, roteiro, ft, medidas, tams, custo) {
  imprimirHtml(`<div class="romaneio"><h1>${h(EMPRESA)} — FICHA TÉCNICA</h1>
    <p><b>${h(prod.nome)}</b>${prod.codigo ? ` · Código ${h(prod.codigo)}` : ''}${fp.referencia ? ` · Ref. ${h(fp.referencia)}` : ''}</p>
    <p>Criação: ${h(fp.criacao || '—')} · Pilotagem: ${h(fp.pilotagem || '—')} · Grade: ${h(fp.grade || '—')}</p>
    ${fp.info_corte ? `<p><b>Informação de corte:</b> ${h(fp.info_corte)}</p>` : ''}
    <div style="display:flex;gap:6mm">${[fp.foto_frente, fp.foto_costas].filter(Boolean).map(u => `<img src="${h(u)}" style="max-height:60mm">`).join('')}</div>
    <h3>Roteiro</h3><table><thead><tr><th>#</th><th>Operação</th><th>Tempo (s)</th></tr></thead><tbody>${roteiro.map(r => `<tr><td>${r.sequencia}</td><td>${h(r.processos?.nome)}</td><td style="text-align:right">${num(r.tempo_seg)}</td></tr>`).join('')}</tbody>
      <tfoot><tr><th colspan="2" style="text-align:right">Total</th><th style="text-align:right">${num(custo.tempo_seg)} s</th></tr></tfoot></table>
    <h3>Matéria-prima</h3><table><thead><tr><th>Item</th><th>Unid.</th><th>Consumo</th><th>Valor</th><th>Custo</th></tr></thead><tbody>${ft.map(x => `<tr><td>${h(x.materias_primas.nome)}</td><td>${h(x.materias_primas.unidade)}</td>
      <td style="text-align:right">${num(x.consumo, 3)}</td><td style="text-align:right">${moeda(x.materias_primas.valor)}</td><td style="text-align:right">${moeda(x.consumo * x.materias_primas.valor)}</td></tr>`).join('')}</tbody>
      <tfoot><tr><th colspan="4" style="text-align:right">Custo MP</th><th style="text-align:right">${moeda(custo.custo_mp)}</th></tr></tfoot></table>
    ${medidas.length ? `<h3>Medidas (cm)</h3><table><thead><tr><th>Descrição</th>${tams.map(t => `<th>${h(t)}</th>`).join('')}</tr></thead><tbody>${medidas.map(m => `<tr><td>${h(m.descricao)}</td>${tams.map(t => `<td style="text-align:right">${h(m.medidas?.[t] ?? '')}</td>`).join('')}</tr>`).join('')}</tbody></table>` : ''}
  </div>`);
}
