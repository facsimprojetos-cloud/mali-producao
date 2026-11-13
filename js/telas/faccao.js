import { db, tem } from '../app.js';
import { h, num, moeda, data, chip, modal, chamar, ler, cadastros, opcoes, toast, hojeISO, pedirTexto, confirmar, distintos, filtroSel, contem, DESTINOS } from '../util.js';

let aba = 'aberto';
let fFac = '', fAtraso = '', busca = '', fProd = '';

export async function render(el) {
  const pode = tem('faccao'), sup = tem('supervisor');
  const cad = await cadastros(db);
  let q = db.from('v_envios').select('*').eq('interna', false).limit(600);
  q = aba === 'aberto' ? q.is('data_retorno', null).order('previsao') : q.not('data_retorno', 'is', null).order('data_retorno', { ascending: false });
  if (aba === 'interna') q = db.from('v_envios').select('*').eq('interna', true).is('data_retorno', null).order('previsao');
  const lista = await ler(q);
  const filtrada = lista.filter(x => (!fFac || String(x.faccao_id) === fFac) && (!fAtraso || x.atraso === fAtraso) && (!fProd || x.produto === fProd)
    && contem(x, ['lote', 'produto', 'cor', 'tamanho', 'faccao'], busca));

  el.innerHTML = `
    <div class="cab"><div><h1>3 - Gestão de Facção</h1><p>O que está nas facções, retornos (parciais ou totais), ocorrências e prazos.</p></div></div>
    <div class="abas">
      <button data-a="aberto" class="${aba === 'aberto' ? 'ativo' : ''}">Em aberto</button>
      <button data-a="interna" class="${aba === 'interna' ? 'ativo' : ''}">Produção interna</button>
      <button data-a="retornados" class="${aba === 'retornados' ? 'ativo' : ''}">Retornados</button>
    </div>
    <div class="filtros">
      ${aba !== 'interna' ? `<label class="campo">Facção<select id="ff">${opcoes(cad.faccoes.filter(f => !f.interna), fFac, 'nome', 'id', 'Todas')}</select></label>` : ''}
      ${filtroSel('fa', 'Prazo', aba === 'retornados' ? ['Entregue no prazo', 'Entregue com atraso'] : ['Atrasado', 'No Prazo'], fAtraso)}
      ${filtroSel('fp', 'Produto', distintos(lista, 'produto'), fProd)}
      <label class="campo">Buscar<input id="fb" value="${h(busca)}" placeholder="Sublote, cor…"></label>
    </div>
    <p class="muted peq">${num(filtrada.length)} envio(s) · ${num(filtrada.reduce((a, e) => a + e.saldo, 0))} peças pendentes · ${num(filtrada.reduce((a, e) => a + e.qtd, 0))} enviadas</p>
    <div id="lista"></div>`;
  el.querySelectorAll('[data-a]').forEach(b => b.onclick = () => { aba = b.dataset.a; fAtraso = ''; render(el); });
  el.querySelector('#ff')?.addEventListener('change', (e) => { fFac = e.target.value; render(el); });
  el.querySelector('#fa').onchange = (e) => { fAtraso = e.target.value; render(el); };
  el.querySelector('#fp').onchange = (e) => { fProd = e.target.value; render(el); };
  el.querySelector('#fb').onchange = (e) => { busca = e.target.value; render(el); };

  const grupos = new Map();
  filtrada.forEach(e => { if (!grupos.has(e.faccao)) grupos.set(e.faccao, []); grupos.get(e.faccao).push(e); });
  el.querySelector('#lista').innerHTML = [...grupos.entries()].map(([fac, itens]) => `
    <h2 style="margin-top:14px">${h(fac)} <span class="muted peq">${num(itens.reduce((a, e) => a + e.saldo, 0))} peças pendentes · ${itens.length} envio(s)</span></h2>
    <div class="tabela-wrap"><table><thead><tr><th>Sublote</th><th>Produto</th><th>Cor</th><th>Tam.</th><th class="n">Enviado</th><th class="n">Boas</th><th class="n">Defeito</th><th class="n">Saldo</th>
      <th>Envio</th><th>Previsão</th><th>Prazo</th><th>Ocorrência</th><th></th></tr></thead>
    <tbody>${itens.map(e => `<tr>
      <td class="forte">${h(e.lote)}</td><td>${h(e.produto)}</td><td>${h(e.cor)}</td><td>${h(e.tamanho)}</td>
      <td class="n">${num(e.qtd)}</td><td class="n">${num(e.qtd_boas)}</td><td class="n">${num(e.qtd_defeito)}</td><td class="n forte">${num(e.saldo)}</td>
      <td>${data(e.remessa_data)}</td><td>${data(e.previsao)}</td>
      <td>${chip(e.atraso + (e.dias_atraso ? ` (${e.dias_atraso}d)` : ''), /atraso|Atrasado/.test(e.atraso) ? 'erro' : 'ok')}</td>
      <td class="peq">${h(e.ocorrencia || '')}</td>
      <td><div class="acoes">
        ${pode && !e.data_retorno && aba !== 'interna' ? `<button class="btn pri peq" data-ret="${e.id}">Retorno</button>` : ''}
        ${pode && !e.data_retorno && aba === 'interna' ? `<button class="btn pri peq" data-ret="${e.id}">Finalizar lote</button>` : ''}
        ${pode && !e.data_retorno ? `<button class="btn peq" data-oc="${e.id}">Ocorrência</button>` : ''}
        ${e.qtd_boas + e.qtd_defeito > 0 ? `<button class="btn peq" data-hist="${e.id}">Retornos</button>` : ''}
        ${pode && !e.data_retorno && e.saldo > 0 && e.qtd_boas + e.qtd_defeito > 0 ? `<button class="btn peq" data-fin="${e.id}">Encerrar saldo</button>` : ''}
        ${sup && e.data_retorno && e.saldo > 0 ? `<button class="btn peq" data-reab="${e.id}">Reabrir</button>` : ''}
        ${sup && e.qtd_boas + e.qtd_defeito === 0 ? `<button class="btn peq perigo" data-del="${e.id}">🗑</button>` : ''}
      </div></td></tr>`).join('')}</tbody></table></div>`).join('') || '<div class="vazio">Nada por aqui.</div>';

  const acha = (id) => filtrada.find(x => x.id === id);
  el.querySelectorAll('[data-ret]').forEach(b => b.onclick = () => formRetorno(acha(b.dataset.ret), cad, () => render(el)));
  el.querySelectorAll('[data-oc]').forEach(b => b.onclick = async () => {
    const e = acha(b.dataset.oc);
    const t = await pedirTexto(`Ocorrência — ${e.lote}`, 'Descreva a ocorrência (deixe em branco e confirme para limpar).', { rotulo: 'Ocorrência', minimo: 0, botao: 'Salvar', classe: 'pri', valor: e.ocorrencia || '' });
    if (t !== null && await chamar(db, 'registrar_ocorrencia', { p_envio_id: e.id, p_texto: t })) { toast('Ocorrência salva.', 'ok'); render(el); }
  });
  el.querySelectorAll('[data-fin]').forEach(b => b.onclick = async () => {
    const e = acha(b.dataset.fin);
    const m = await pedirTexto(`Encerrar envio ${e.lote}`, `Ainda faltam <b>${e.saldo}</b> peças. Encerrar o envio assim mesmo (peças perdidas/não devolvidas)?`, { botao: 'Encerrar' });
    if (m && await chamar(db, 'finalizar_envio', { p_envio_id: e.id, p_motivo: m })) { toast('Envio encerrado.', 'ok'); render(el); }
  });
  el.querySelectorAll('[data-reab]').forEach(b => b.onclick = async () => {
    if (await chamar(db, 'reabrir_envio', { p_envio_id: b.dataset.reab })) { toast('Envio reaberto.', 'ok'); render(el); }
  });
  el.querySelectorAll('[data-del]').forEach(b => b.onclick = async () => {
    const e = acha(b.dataset.del);
    const m = await pedirTexto(`Excluir envio ${e.lote}`, `As ${e.qtd} peças voltam para "Aguardando distribuição".`, { botao: 'Excluir envio' });
    if (m && await chamar(db, 'excluir_envio', { p_envio_id: e.id, p_motivo: m })) { toast('Envio excluído.', 'ok'); render(el); }
  });
  el.querySelectorAll('[data-hist]').forEach(b => b.onclick = () => historico(acha(b.dataset.hist), () => render(el)));
}

export function destinoPadrao(produto) {
  return produto?.estamparia_apos ? 'ESTAMPARIA' : 'INSPEÇÃO';
}

function formRetorno(e, cad, depois) {
  const prod = cad.produtos.find(p => p.id === e.produto_id);
  const padrao = destinoPadrao(prod);
  modal({
    titulo: `${e.interna ? 'Finalizar lote interno' : 'Retorno da facção'} — ${e.lote}`,
    corpo: `<p>${h(e.faccao)} · ${h(e.produto)} ${h(e.cor)} ${h(e.tamanho)} · enviado <b>${e.qtd}</b> · pendente <b>${e.saldo}</b></p>
      <form id="fr" class="grade g2">
        <label class="campo">Peças boas<input type="number" name="qtd" min="0" max="${e.saldo}" value="${e.saldo}" required></label>
        <label class="campo">Com defeito (vão para conserto)<input type="number" name="def" min="0" max="${e.saldo}" value="0"></label>
        <label class="campo">Próximo processo<select name="prox">${Object.entries(DESTINOS).map(([k, r]) => `<option value="${k}" ${k === padrao ? 'selected' : ''}>${r}</option>`).join('')}</select></label>
        <label class="campo">Data do retorno<input type="date" name="data" value="${hojeISO()}" max="${hojeISO()}"></label>
        <label class="campo" style="grid-column:1/-1">Observação<input name="obs"></label>
      </form>
      ${e.valor_unit > 0 ? `<p class="muted peq">Valor a pagar: peças boas × ${moeda(e.valor_unit)}. As peças com defeito voltam para a mesma facção e são pagas quando retornarem consertadas.</p>` : ''}`,
    botoes: [{ texto: 'Cancelar' }, { texto: 'Registrar', classe: 'pri', acao: async (m) => {
      const f = m.querySelector('#fr'); if (!f.reportValidity()) return false;
      const qtd = +f.qtd.value, def = +f.def.value || 0;
      if (qtd + def <= 0 || qtd + def > e.saldo) { toast(`Boas + defeito deve ficar entre 1 e ${e.saldo}.`, 'erro'); return false; }
      if (!await chamar(db, 'registrar_retorno', { p_envio_id: e.id, p_qtd: qtd, p_defeito: def, p_proximo: f.prox.value, p_data: f.data.value || null, p_obs: f.obs.value || null })) return false;
      toast(`Retorno registrado. ${qtd} peça(s) → ${DESTINOS[f.prox.value]}.`, 'ok'); depois();
    } }]
  });
}

async function historico(e, depois) {
  const rets = await ler(db.from('v_retornos').select('*').eq('envio_id', e.id).order('criado_em'));
  const sup = tem('supervisor');
  const m = modal({ titulo: `Retornos de ${e.lote}`, largo: true, corpo: `<div class="tabela-wrap"><table>
    <thead><tr><th>Data</th><th class="n">Boas</th><th class="n">Defeito</th><th>Destino</th><th class="n">Valor</th><th>Pago</th><th>Obs.</th><th></th></tr></thead>
    <tbody>${rets.map(r => `<tr><td>${data(r.data_retorno)}</td><td class="n">${num(r.qtd)}</td><td class="n">${num(r.qtd_defeito)}</td><td>${h(DESTINOS[r.proximo])}</td>
      <td class="n">${moeda(r.valor_a_pagar)}</td><td>${r.pago ? chip('Pago', 'ok') : chip('A pagar', 'info')}</td><td class="peq">${h(r.obs || '')}</td>
      <td>${sup && !r.pago ? `<button class="btn peq perigo" data-x="${r.id}">🗑</button>` : ''}</td></tr>`).join('')}</tbody></table></div>` });
  m.el.querySelectorAll('[data-x]').forEach(b => b.onclick = async () => {
    const mt = await pedirTexto('Excluir retorno', 'As peças voltam a ficar pendentes na facção. Só é possível se a etapa seguinte não começou.', { botao: 'Excluir retorno' });
    if (mt && await chamar(db, 'excluir_retorno', { p_retorno_id: b.dataset.x, p_motivo: mt })) { toast('Retorno excluído.', 'ok'); m.fechar(); depois(); }
  });
}
