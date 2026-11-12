import { db, ctx } from '../app.js';
import { h, dataHora, chip, modal, ler, toast, msgErro, chamar } from '../util.js';

const PERFIS = [
  ['admin', 'Administrador (tudo)'], ['supervisor', 'Supervisor (estornar e excluir lançamentos)'], ['cadastros', 'Cadastros e ficha técnica'],
  ['comercial', 'Comercial (pedidos e clientes)'], ['corte', 'Corte'], ['faccao', 'Facção / envios / retornos / consertos'],
  ['producao', 'Produção interna (apontamentos)'], ['estamparia', 'Estamparia'], ['qualidade', 'Finalização e inspeção'],
  ['estoque', 'Estoque e expedição'], ['financeiro', 'Financeiro (fechamento)'],
];

export async function render(el) {
  const [usuarios, pendentes] = await Promise.all([
    ler(db.from('usuarios').select('*').order('nome')),
    chamar(db, 'contas_pendentes', {}).then(r => r || []),
  ]);
  el.innerHTML = `
    <div class="cab"><div><h1>Usuários</h1><p>Quem cria conta na tela de login aparece em "Aguardando liberação". Sem perfil, a pessoa só consulta.</p></div></div>
    ${pendentes.length ? `<div class="card"><h2>Aguardando liberação</h2>
      <div class="tabela-wrap"><table><thead><tr><th>E-mail</th><th>Criada em</th><th></th></tr></thead>
      <tbody>${pendentes.map(p => `<tr><td>${h(p.email)}</td><td>${dataHora(p.criado_em)}</td><td><button class="btn pri peq" data-lib="${p.id}">Liberar</button></td></tr>`).join('')}</tbody></table></div></div>` : ''}
    <div class="tabela-wrap"><table><thead><tr><th>Nome</th><th>E-mail</th><th>Perfis</th><th>Status</th><th></th></tr></thead>
      <tbody>${usuarios.map(u => `<tr><td class="forte">${h(u.nome)}</td><td>${h(u.email || '')}</td><td>${u.perfis.map(p => chip(p, p === 'admin' ? 'acento' : 'info')).join(' ')}</td>
        <td>${u.ativo ? chip('Ativo', 'ok') : chip('Inativo', 'erro')}</td><td><button class="btn peq" data-ed="${u.id}">Editar</button></td></tr>`).join('')}</tbody></table></div>`;
  el.querySelectorAll('[data-lib]').forEach(b => b.onclick = () => form(null, pendentes.find(p => p.id === b.dataset.lib), () => render(el)));
  el.querySelectorAll('[data-ed]').forEach(b => b.onclick = () => form(usuarios.find(u => u.id === b.dataset.ed), null, () => render(el)));
}

function form(u, pend, depois) {
  const perfis = u?.perfis || [];
  modal({
    titulo: u ? `Editar ${u.nome}` : `Liberar ${pend.email}`,
    corpo: `<form id="fu" class="grade">
      <label class="campo">Nome<input name="nome" value="${h(u?.nome || '')}" required></label>
      <div><b>Perfis</b>${PERFIS.map(([k, r]) => `<label style="display:block;margin:6px 0"><input type="checkbox" name="perfil" value="${k}" ${perfis.includes(k) ? 'checked' : ''}> ${r}</label>`).join('')}</div>
      ${u ? `<label><input type="checkbox" name="ativo" ${u.ativo ? 'checked' : ''}> Acesso ativo</label>` : ''}
    </form>`,
    botoes: [{ texto: 'Cancelar' }, {
      texto: 'Salvar', classe: 'pri', acao: async (m) => {
        const f = m.querySelector('#fu'); if (!f.reportValidity()) return false;
        const sel = [...f.querySelectorAll('[name=perfil]:checked')].map(i => i.value);
        if (u && u.id === ctx.usuario.id && (!sel.includes('admin') || !f.ativo.checked)) { toast('Você não pode remover o seu próprio acesso de administrador.', 'erro'); return false; }
        if (!await chamar(db, 'salvar_usuario', { p_id: u ? u.id : pend.id, p_nome: f.nome.value.trim(), p_perfis: sel, p_ativo: u ? f.ativo.checked : true })) return false;
        toast('Usuário salvo.', 'ok'); depois();
      }
    }]
  });
}
