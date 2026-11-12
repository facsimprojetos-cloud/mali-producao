import { db } from '../app.js';
import { h, num, moeda, data, chip, ler, chamar } from '../util.js';

export async function render(el) {
  const [p, atrasados, pedidos] = await Promise.all([
    chamar(db, 'painel', {}),
    ler(db.from('v_envios').select('faccao,lote,produto,cor,tamanho,saldo,previsao,dias_atraso').eq('atraso', 'Atrasado').order('previsao').limit(15)),
    ler(db.from('v_pedidos').select('*').eq('status', 'Aberto').order('entrega').limit(10)),
  ]);
  if (!p) return;
  const et = p.etapas || {};
  const kpi = (rot, val, link, tipo = '') => `<a class="kpi ${tipo}" href="${link}"><div class="rot">${h(rot)}</div><div class="val">${val}</div></a>`;
  el.innerHTML = `
    <div class="cab"><div><h1>Painel</h1><p>Visão geral da produção agora.</p></div></div>
    <div class="grade g4">
      ${kpi('Pedidos abertos', num(p.pedidos_abertos), '#/pedidos')}
      ${kpi('Pedidos atrasados', num(p.pedidos_atrasados), '#/pedidos', p.pedidos_atrasados ? 'erro' : 'ok')}
      ${kpi('Cortes programados', num(p.cortes_programados), '#/corte')}
      ${kpi('Peças aguardando distribuição', num(p.pecas_aguardando_distribuicao), '#/lotes', p.pecas_aguardando_distribuicao ? 'alerta' : '')}
      ${kpi('Peças em facção', num(p.pecas_em_faccao), '#/faccao')}
      ${kpi('Envios atrasados', num(p.envios_atrasados), '#/faccao', p.envios_atrasados ? 'erro' : 'ok')}
      ${kpi('Em conserto', num(p.em_conserto), '#/consertos', p.em_conserto ? 'alerta' : '')}
      ${kpi('Na estamparia', num(et['ESTAMPARIA'] || 0), '#/estamparia')}
      ${kpi('Na finalização', num(et['FINALIZAÇÃO'] || 0), '#/finalizacao')}
      ${kpi('Na inspeção', num(et['INSPEÇÃO'] || 0), '#/inspecao')}
      ${kpi('Peças em estoque', num(p.estoque_total), '#/estoque', 'ok')}
      ${kpi('Expedições pendentes', num(p.expedicoes_pendentes), '#/expedicao')}
      ${kpi('Operadores trabalhando', num(p.operadores_trabalhando), '#/producao')}
      ${kpi('Produzido hoje (interno)', num(p.producao_hoje), '#/producao')}
      ${kpi('A pagar às facções', moeda(p.a_pagar), '#/fechamento')}
    </div>
    <div class="grade g2" style="margin-top:16px">
      <div class="card"><h2>Envios atrasados</h2>
        <div class="tabela-wrap"><table><thead><tr><th>Facção</th><th>Sublote</th><th>Produto</th><th class="n">Saldo</th><th>Previsão</th></tr></thead>
        <tbody>${atrasados.map(e => `<tr><td>${h(e.faccao)}</td><td>${h(e.lote)}</td><td>${h(e.produto)} ${h(e.cor)} ${h(e.tamanho)}</td>
          <td class="n">${num(e.saldo)}</td><td>${data(e.previsao)} ${chip(e.dias_atraso + 'd', 'erro')}</td></tr>`).join('') || '<tr><td colspan="5" class="vazio">Nenhum envio atrasado.</td></tr>'}</tbody></table></div></div>
      <div class="card"><h2>Pedidos por entrega</h2>
        <div class="tabela-wrap"><table><thead><tr><th>Nº</th><th>Cliente</th><th>Entrega</th><th class="n">Entregue</th></tr></thead>
        <tbody>${pedidos.map(x => `<tr><td class="forte">${x.numero}</td><td>${h(x.cliente)}</td><td>${data(x.entrega)} ${x.atrasado ? chip('Atrasado', 'erro') : ''}</td>
          <td class="n">${num(x.qtd_entregue)} / ${num(x.qtd_total)}</td></tr>`).join('') || '<tr><td colspan="4" class="vazio">Nenhum pedido aberto.</td></tr>'}</tbody></table></div></div>
    </div>`;
}
