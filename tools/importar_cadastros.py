# Gera supabase/seed_cadastros.sql com os cadastros reais da planilha "APP MALI" (lidos em 12/11/2026)
def q(v):
    if v is None or v == '': return 'null'
    return "'" + str(v).replace("'", "''") + "'"
def num(v):
    if not v: return 'null'
    v = v.replace('R$','').replace('.','').replace(',','.').strip()
    return v or 'null'

clientes = [('a1','PATRICK'),('263d46d3','MALI')]
cores = """933adf90 BRANCO|010bcd72 AZUL|0654948d VERDE|28dcad3b ROXO|d9b2787b PRETO|f3bb9f36 RUBRO|d2aa5c16 MARINHO|9d0bb639 CHUMBO|691dc3fa FROZEN|5f7f2397 ROSA|8054e76e PINK|e5078614 OLIVA|afc5097c LIMA|99bbfa84 FANTÁSTICO|96645446 GRAFITE|1f095ea8 MESCLA|182df69e ESTAMPADO FLORAL|f4af38e9 ROMANCE|2414123c TEOS|358fbc72 RUBI|846f2954 LILÁS|f43216a4 ROSA BB|91fba487 CHOCOLATE|fe313a27 VERMELHO|d90f1ba5 MARROM|8143546c CASTANHO|3bf8d0ae ODALISCA|35106636 ROYAL|58599206 VERMELHO 1|26458ebd VERMELHO 2|cf55e2bc PRETO 1|6375cbac PRETO 2|6fa176cc FROZEN 1|9582cdf3 FROZEN 2|0e90ed47 RUBI 1|e9287ffb RUBI 2|9deda2ce SALMON|e41f5f9c PRETO 3|74560196 RUBRO 2|29640475 MARROM 2|c177da17 MARROM 1|4103b9eb MARINHO 2|27591051 MARINHO 1|3cb05584 RUBRO 1|f2ccc3ca SENSUALI|9a478c55 MILITAR|de10d657 JEANS|72dc5cc3 GRAFITE 2|6705dcfd GRAFIT 1|298bcbb9 AZULEJO|a0b067ed ONÇA|956d0881 CHUMBO 2|717e2b54 OLIVA 2|bed9bcef CHUMBO 1|5228da75 OLIVA 1|c9c73e98 CHOCOLATE 2|941c847f PRETO 4|ca3e35ee ROMANCE 2|3b0d8414 ODALISCA 2|3842a6ba MESCLA 2|bbcb0005 MESCLA 1|19261d62 OLIVA 3|7a316605 RUBRO 3|b44c69af PRETO 6|11c94a1d PRETO 5|7f3fe352 MARINHO 3|e5007481 GRAFITE 3|3feaeea5 MESCLA 3|edbeb764 PRETO 7|47dd4a51 ROYAL 2|d9dba511 ROYAL 1|0fc4f754 ROYAL 3|2768dd99 MARROM 3|8decfac5 MARROM 4|6e69beef ROYAL 4|6d2f9cbc MESCLA 3|245a60c3 MESCLA 6|95cc7f61 MESCLA 4|7b20416c MESCLA 5|bfe9c85f MARROM|557b3b2b MILITAR 1|933ea3df AZUL BIC|65f61782 SORTIDOS|ab064e66 OLIVA 5|2243111a RUBRO 4|6d998a10 OLIVA 4|6b05acee CHOCOLATE 5|61d0b98c CHOCOLATE 3|119725be MARINHO 4|03ed42a6 CHOCOLATE 4|b77e9f64 PRETO 8|7a301a55 MARROM 5|41605ba6 AZUL2|02af7327 VULCANO|5ecb3300 MERLOT|a78c2cb4 MARAGOGI|551c2127 PANTERA|d32b14eb ROSA2|417a3654 LILAS1|9dc679b9 PINK1|26fbefff ROSA1|aaa5e1c4 CHOCOLATE 1|3c2289dd VINO|e1b40b71 VINHO 1|f1ea80c7 MERLOT 1|f601668b VINHO|6be89a4b CAPPUCCINO|dfaef4ff VERDE MILITAR|44149634 AMARELO BISCOITO|b536def9 MERLOT 4|bc19764f MERLOT 2|ec48e441 MERLOT 3"""
cores = [c.split(' ',1) for c in cores.split('|')]
tamanhos = [('d2614e9f','P',1),('25cfd751','M',2),('6067e9d1','G',3),('1332729d','GG',4)]
# (legado, codigo, nome, preco, estamparia_apos)
produtos = [('A1','TP001','TOP VIRGÍNIA','11,4','SIM'),('6fbc81fb','CS001','CASACO CANGURU','','SIM'),('f15cc782','','CALÇA JOGGER','','SIM'),
('4a3eaba1','','SHORT BD. AMAMENTAÇÃO','','SIM'),('f2ae9812','','SHORT CRIS','','SIM'),('863e153d','','CALÇA LEGGING','','SIM'),('bf5c0eaf','','SHORT VIRGINIA','','SIM'),
('0b482526','','TOP CAROL','','SIM'),('6de7fe9e','','SHORT CAROL','','SIM'),('23b1bf79','','TOP DOOL RENDA VIRGINIA','','SIM'),('d83593ae','','CUECA BOX MASCULINA INFANTIL','','SIM'),
('a9375bd4','','CALEÇON','','SIM'),('9bc77bfe','','CONJUNTO SUEDE','','SIM'),('9d1b7253','','TANGA LASER','','SIM'),('25f65aac','','BLUSA SUEDE','','SIM'),('e10d82aa','','SHORT SUEDE','','SIM'),
('9228be3d','','MACAQUINHO','','SIM'),('9a786ff2','','BLUSA BD. AMAMENTAÇÃO','','NÃO'),('7af5d3b8','','CAMISA TULE','','SIM'),('3320dc2a','','CROPPED TULE','','SIM'),('8e9b147c','','SHORT ONDINHA','','SIM'),
('05f085b7','','CALÇOLINHA','','SIM'),('7348265c','','BLUSA ONDINHA','','SIM'),('8b4693a0','','BLUSA BLOGUEIRA','','SIM'),('2d5b9891','','SHORT BLOGUEIRA','','SIM'),('8117cc39','','TESTE JU','','SIM'),
('a15b72a5','','CALÇA LEGGING DUO','','SIM'),('300fb05d','','CALÇA LEGGING BLACK OUT','','SIM'),('64ad3b63','','CUECA BOX FEMININA','','SIM'),('d10074b4','','TOP APROVEITAMENTO','','SIM'),
('42f88c3d','','TOP TESTE','','SIM'),('fa07743a','','CALÇA PIJAMA','','NÃO'),('e62123c7','','CALÇA PIJAMA AMAMENTAÇÃO','','NÃO'),('37ea3889','','BLUSA PIJAMA AMAMENTAÇÃO','','NÃO'),
('9794b0a0','','CAMISOLA AMAMENTAÇÃO','','NÃO'),('93cc48b9','','BLUSA PIJAMA','','NÃO'),('68d8ecaf','','TOMARA QUE CAIA','','SIM'),('79423dfd','','CAMISETA FITURBAN','',''),
('8e3471c7','','TANGA COSTA DUPLA','',''),('77c62bad','','CALÇA LEGGING BOLSO BLACKOUT','',''),('b462c680','','CONJUNTO CAROL','',''),('97224210','','LEGGING MICRO CANELADO','',''),
('5233e60c','','TOP MICRO CANELADO','',''),('246655f6','','TOP APROVEITAMENTO MICRO CANELADO','','')]
TESTES = {'TESTE JU','TOP TESTE'}
# (legado, numero, nome, endereco, telefone, maquinas, pix, capacidade)
faccoes = [('10','10','Adriana Pires Ferreira da Silva','DEBOSSAN','','OVERLOCK, RETA, COLARETE','22998167269','100'),('F9','25','Amanda','Jardinlandia','','8 Overlok','','100'),
('F2','2','Ana Angélica Cirino Sandre Risso','','22981350116','(2) Overlok','22996097958','200'),('F1','22','Ana Cristina Marinho Monteiro','Rua Eugênio Couto 47 Chácara','22992374000','(1) overlock e colarete','22999862920','700'),
('13','11','Cristiane Castro Couto','','','TODAS','22742037764 Karina','300'),('11','4','Cristiane Rodrigues Pereira','Rua Carmen Ruiz de Barros,83/Prado','22981249869','overloque','22981249869',''),
('12','20','Elaine','','','','',''),('F3','3','Írisdalva Meireles de Souza','Rua Carmem Ruiz de Barros,83 Prado','22988242279','(3) Overlok','22988242279','700'),
('16','7','Janaina Vianna da Silva','Rua Edith Pinheiro de Faria','22997660281','overlook / colarete','08638182775',''),
('18','13','Jessica Freitas','Travessa andrelino viana da silva 385 - Chácara do paraíso / Rua em frente ao moinho de vento Casa 6 fundos','22997677781','overlook','22997677781','100'),
('000022','9','Juliana Ferreira','Rua Fernandes Ennes 660 ap 1 qd 2 Cordoeira','22996043664','','22996043664',''),('17','12','Ludimar Carneiro da Silva','Rua Augusto severo 28, Centro','22999910501','overlook colarete reta traveti','22999910501',''),
('F8','24','Márcia Vigante','Rua Érico Veríssimo ,82 Jardiândia','22992510229','(7)Overlock','Ag 1623 C/C 000588261204-3 Caixa Econômica','150'),('F6','5','Marciana Furtado da Costa','','','(5) OVERLOCK','11880108755','500'),
('012','23','Michele','','','OVERLOCK','','300'),('F10','1','PRODUÇÃO INTERNA','','','','',''),('6','6','Roberta Kelly da Silva Correia','R. Nahuel Moreno, 17 Rui Sanglard','','COLARETE E OVERLOCK','22988145165','400'),
('F5','21','Tereza','','22997386871','(4) Overlok/Colaret/Travet','','500'),('22','14','TESTE /FACÇÕES','','','','',''),('14','8','Valéria dos Santos Azevedo','','','OVERLOCK','22 99848-4361','100')]
operadores = ['Daniela Souza','Priscila Tatiana','Tainá Pedroso','Paula Ketlin','Bianca Ferreira','Vaniele Ribeiro','Gabriela Pinheiro']
processos = """FECHAMENTO EP|GANCHO|APLICAÇÃO CÓS|LATERAL C|LATERAL|SANDUICHE|BAINHA BOLSO|BAINHA PERNA|FAZER ETIQUETA|CÓS COM ELASTICO|PASSAR ELÁSTICO NO MEIO|PREGAR FORRO|FECHAR LATERAL ESQUERDA|PASSAR ELÁSTICO NA BASE|FECHAR LATERAL ESQUERDA COM ETIQUETA|MONTAR CÓS|GAVIÃO FRENTE|GAVIÃO COSTA|MONTAR PÉZINHO|GANCHO FRENTE|FECHAR BOLSO|PREGAR E CHULEAR BOLSO|FECHAR LATERAIS|FAZER CÓS|PREGAR CÓS|FAZER BAINHA INVERTIDA|EMENDAR CADARÇO|FAZER CADARÇO|CORTAR CADARÇO|REVISAR|EMBALAR|PREGAR PEZINHO|FECHAR CAPUZ|BAINHA CAPUZ|PREGAR BOLSO RETA|FECHAR CÓIS|FECHAR PUNHO|OMBROS|CHULEAR CAPUZ|PREGAR CAPUZ|PREGAR MANGAS|PREGAR PUNHO|PREGAR CÓIS|FECHAR LATERAL DIREITA|REBATER ELÁSTICO|PASSAR VIÉS|TRAVETAR ALÇA|UNIR OMBRO|REBATER ELÁSTICO BASE|PREGAR VIÉS DECOTE + COSTAS + CAVAS + ALÇAS|MEDIR E MARCAR AS ALÇAS|ARREMATAR ALÇAS 2X|REVISAR E LIMPAR|TAG|FECHAR LATERAL E ENTRE PERNAS|PREGAR PÉZINHO|FAZER VIÉS|TRAVETAR VIÉS""".split('|')
moletom = ['FECHAR CAPUZ','BAINHA BOLSO','BAINHA CAPUZ','PREGAR BOLSO RETA','UNIR OMBRO','PREGAR CAPUZ','PREGAR MANGAS','FECHAR LATERAIS','FECHAR PUNHO','FECHAR CÓIS','PREGAR PUNHO','PREGAR CÓS','REVISAR','EMBALAR']
roteiros = {
 'TOP VIRGÍNIA': [('PASSAR ELÁSTICO NO MEIO',129),('PREGAR FORRO',77),('FECHAR LATERAL ESQUERDA COM ETIQUETA',13),('PASSAR ELÁSTICO NA BASE',14),('FECHAR LATERAL DIREITA',10),('REBATER ELÁSTICO BASE',12),('PREGAR VIÉS DECOTE + COSTAS + CAVAS + ALÇAS',9),('MEDIR E MARCAR AS ALÇAS',10),('ARREMATAR ALÇAS 2X',10),('REVISAR E LIMPAR',10),('EMBALAR',10),('TAG',10)],
 'CALÇA JOGGER': [('MONTAR CÓS',126),('GAVIÃO FRENTE',77),('GAVIÃO COSTA',13),('MONTAR PÉZINHO',140),('FECHAR BOLSO',10),('PREGAR E CHULEAR BOLSO',12),('FECHAR LATERAL E ENTRE PERNAS',9),('PREGAR CÓS',10),('PREGAR PÉZINHO',10),('FAZER VIÉS',10),('TRAVETAR VIÉS',10),('TAG',10)],
 'CASACO CANGURU': [(p,10) for p in moletom],
 'SHORT CAROL': [(p,10) for p in moletom],
 'BLUSA BD. AMAMENTAÇÃO': [(p,10) for p in moletom],
}
# matéria-prima (legado, nome, unidade, valor, tipo, rendimento, largura, gramatura, fornecedor)
mps = [('a3be069a','LAÇO','UNIDADE','1,20','ACESSÓRIO','','','',''),('7bbcdf35','SUPLEX','KG','50,00','TECIDO','','','',''),('30a1953d','SUEDE ESTAMPADO','KG','27,90','TECIDO','','','',''),
('ff8aad6d','ELÁSTICO SERRINHA','METRO','0,20','AVIAMENTO','','','',''),('d8ac7344','ELÁSTICO SANDUICHE','METRO','0,20','AVIAMENTO','','','',''),('d8ac7345','ALÇA AMAMENTAÇÃO','UNIDADE','0,50','AVIAMENTO','','','',''),
('d9a23641','MOLETOM','KG','23,00','TECIDO','1,5','1,88','250','Fornecedor 1')]
ficha = [('bf5c0eaf','30a1953d','0,3'),('bf5c0eaf','ff8aad6d','1,2'),('6fbc81fb','d9a23641','0,8'),('6fbc81fb','a3be069a','2'),('4a3eaba1','30a1953d','0,3'),('4a3eaba1','d8ac7344','1,5'),('4a3eaba1','d8ac7345','1'),('bf5c0eaf','a3be069a','2')]
fichas_prod = [('42f88c3d','041','RAMON FREITAS','CRISTIANE CASTRO','P, M, G, GG','NÃO ENFESTAR ESPELHADO / COSTAS PARA ESTAMPARIA (MALI) / FRENTE PARA ESTAMPARIA (SACOLEIRO)'),
('6fbc81fb','BL22','RAMON','RAMON','M, G, GG','DEIXAR LINHAS DA OVERLOQUE'),('23b1bf79','TPD','','','P, M, G','')]

o = ['-- Cadastros reais importados da planilha APP MALI (gerado por tools/importar_cadastros.py)', 'begin;']
o += [f"insert into mali.clientes(nome, legado_id) values ({q(n)}, {q(l)}) on conflict (nome) do nothing;" for l,n in clientes]
o += [f"insert into mali.cores(nome, legado_id) values ({q(n.strip())}, {q(l)}) on conflict (nome) do nothing;" for l,n in cores]
o += [f"insert into mali.tamanhos(nome, ordem, legado_id) values ({q(n)}, {o_}, {q(l)}) on conflict (nome) do nothing;" for l,n,o_ in tamanhos]
o += [f"insert into mali.produtos(codigo, nome, preco, estamparia_apos, ativo, legado_id) values ({q(c)}, {q(n)}, {num(p)}, {'true' if e=='SIM' else 'false'}, {'false' if n in TESTES else 'true'}, {q(l)}) on conflict (nome) do nothing;" for l,c,n,p,e in produtos]
for l,nu,n,en,te,ma,px,ca in faccoes:
    o.append(f"insert into mali.faccoes(numero, nome, endereco, telefone, maquinas, pix, capacidade, interna, ativo, legado_id) values ({nu}, {q(n)}, {q(en)}, {q(te)}, {q(ma)}, {q(px)}, {ca or 'null'}, {'true' if n=='PRODUÇÃO INTERNA' else 'false'}, {'false' if 'TESTE' in n else 'true'}, {q(l)}) on conflict (nome) do nothing;")
o += [f"insert into mali.operadores(nome) values ({q(n)}) on conflict (nome) do nothing;" for n in operadores]
o += [f"insert into mali.processos(nome) values ({q(n)}) on conflict (nome) do nothing;" for n in processos]
o += ["insert into mali.motivos_parada(nome, duracao_min) values ('Fim de Expediente', 510), ('Café Manhã', 15), ('Café Tarde', 15), ('Almoço', 60), ('Falta de material', null), ('Manutenção de máquina', null) on conflict (nome) do nothing;"]
for prod, ops in roteiros.items():
    for i,(pn,t) in enumerate(ops,1):
        o.append(f"insert into mali.produto_processos(produto_id, processo_id, sequencia, tempo_seg) select p.id, x.id, {i}, {t} from mali.produtos p, mali.processos x where p.nome = {q(prod)} and x.nome = {q(pn)} on conflict do nothing;")
o += [f"insert into mali.materias_primas(nome, unidade, valor, tipo, rendimento, largura, gramatura, fornecedor, legado_id) values ({q(n)}, {q(u)}, {num(v)}, {q(t)}, {num(r)}, {num(la)}, {num(g)}, {q(f)}, {q(l)});" for l,n,u,v,t,r,la,g,f in mps]
o += [f"insert into mali.ficha_tecnica(produto_id, materia_prima_id, consumo) select p.id, m.id, {num(c)} from mali.produtos p, mali.materias_primas m where p.legado_id = {q(pl)} and m.legado_id = {q(ml)} on conflict do nothing;" for pl,ml,c in ficha]
o += [f"insert into mali.fichas_produto(produto_id, referencia, criacao, pilotagem, grade, info_corte) select id, {q(r)}, {q(c)}, {q(pi)}, {q(g)}, {q(i)} from mali.produtos where legado_id = {q(pl)} on conflict do nothing;" for pl,r,c,pi,g,i in fichas_prod]
o.append('commit;')
open('supabase/seed_cadastros.sql','w').write('\n'.join(o)+'\n')
print(len(o), 'linhas')

# Versão compacta (mesmo conteúdo, em blocos VALUES) para colar no SQL editor / MCP
c = ['begin;']
c.append("insert into mali.clientes(nome, legado_id) values " + ','.join(f"({q(n)},{q(l)})" for l,n in clientes) + " on conflict (nome) do nothing;")
c.append("insert into mali.cores(nome, legado_id) values " + ','.join(f"({q(n.strip())},{q(l)})" for l,n in cores) + " on conflict (nome) do nothing;")
c.append("insert into mali.tamanhos(nome, ordem, legado_id) values " + ','.join(f"({q(n)},{o_},{q(l)})" for l,n,o_ in tamanhos) + " on conflict (nome) do nothing;")
c.append("insert into mali.produtos(codigo, nome, preco, estamparia_apos, ativo, legado_id) values " + ','.join(f"({q(cc)},{q(n)},{num(p)},{'true' if e=='SIM' else 'false'},{'false' if n in TESTES else 'true'},{q(l)})" for l,cc,n,p,e in produtos) + " on conflict (nome) do nothing;")
c.append("insert into mali.faccoes(numero, nome, endereco, telefone, maquinas, pix, capacidade, interna, ativo, legado_id) values " + ','.join(f"({nu},{q(n)},{q(en)},{q(te)},{q(ma)},{q(px)},{ca or 'null'},{'true' if n=='PRODUÇÃO INTERNA' else 'false'},{'false' if 'TESTE' in n else 'true'},{q(l)})" for l,nu,n,en,te,ma,px,ca in faccoes) + " on conflict (nome) do nothing;")
c.append("insert into mali.operadores(nome) values " + ','.join(f"({q(n)})" for n in operadores) + " on conflict (nome) do nothing;")
c.append("insert into mali.processos(nome) values " + ','.join(f"({q(n)})" for n in processos) + " on conflict (nome) do nothing;")
c.append(o[[i for i,x in enumerate(o) if 'motivos_parada' in x][0]])
rows = []
for prod, ops in roteiros.items():
    for i,(pn,t) in enumerate(ops,1): rows.append(f"({q(prod)},{q(pn)},{i},{t})")
c.append("insert into mali.produto_processos(produto_id, processo_id, sequencia, tempo_seg) select p.id, x.id, v.s, v.t from (values " + ','.join(rows) + ") v(prod,proc,s,t) join mali.produtos p on p.nome = v.prod join mali.processos x on x.nome = v.proc on conflict do nothing;")
c.append("insert into mali.materias_primas(nome, unidade, valor, tipo, rendimento, largura, gramatura, fornecedor, legado_id) values " + ','.join(f"({q(n)},{q(u)},{num(v)},{q(t)},{num(r)},{num(la)},{num(g)},{q(f)},{q(l)})" for l,n,u,v,t,r,la,g,f in mps) + ";")
c.append("insert into mali.ficha_tecnica(produto_id, materia_prima_id, consumo) select p.id, m.id, v.c from (values " + ','.join(f"({q(pl)},{q(ml)},{num(cc)})" for pl,ml,cc in ficha) + ") v(pl,ml,c) join mali.produtos p on p.legado_id = v.pl join mali.materias_primas m on m.legado_id = v.ml on conflict do nothing;")
c.append("insert into mali.fichas_produto(produto_id, referencia, criacao, pilotagem, grade, info_corte) select p.id, v.r, v.c, v.pi, v.g, v.i from (values " + ','.join(f"({q(pl)},{q(r)},{q(cc)},{q(pi)},{q(g)},{q(i)})" for pl,r,cc,pi,g,i in fichas_prod) + ") v(pl,r,c,pi,g,i) join mali.produtos p on p.legado_id = v.pl on conflict do nothing;")
c.append('commit;')
open('supabase/seed_cadastros.sql','w').write('-- Cadastros reais importados da planilha APP MALI (gerado por tools/importar_cadastros.py)\n' + '\n'.join(c) + '\n')
