# language: pt
Funcionalidade: Exibir Material de apoio
Como um usuario do solar
Eu quero visualizar o material de apoio
Para poder acessá-las


Contexto:
Dado que tenho "allocations"
| user_id | allocation_tag_id | profile_id | status |
|    1    |         3         |     1      |    1   |
|    1    |         1         |     1      |    1   |
|    1    |         9         |     1      |    1   |

Cenário: Exibir Material de apoio
   Dado que estou logado com o usuario "user" e com a senha "123456"
   E que estou em "Meu Solar"
       Quando eu clicar no link "Quimica I"
   Então eu deverei ver "Conteúdo"
       Quando eu clicar no link "Conteúdo"
   Então eu deverei ver o link "Material de Apoio"
       Quando eu clicar no link "Material de Apoio"
   Então eu deverei ver "AULAS"
      E eu deverei ver o link "2.pdf"
      E eu deverei ver "LINKS"
      E eu deverei ver o link "http://www.google.com"
      E eu deverei ver "OUTRA PASTA"
      E eu deverei ver o link "3.pdf"


#COMBOBOX-TESTE1
Cenário: Trocar material de apoio com a combo
    Dado que estou logado com o usuario "user" e com a senha "123456"
    E que estou em "Meu Solar"
        Quando eu clicar no link "Introducao a Linguistica"
    E que eu selecionei "selected_group" com "FOR - 2012.1"
    Então eu deverei ver "Conteúdo"
        Quando eu clicar no link "Conteúdo"
    Então eu deverei ver o link "Material de Apoio"
        Quando eu clicar no link "Material de Apoio"
            Então eu deverei ver "AULAS"
            E eu deverei ver o link "1.pdf"

#COMBOBOX-TESTE2
@selenium
Cenário: Trocar material de apoio com a combo - parte 2
    Dado que estou logado com o usuario "user" e com a senha "123456"
    E que estou em "Meu Solar"
        Quando eu clicar no link "Introducao a Linguistica"
    E que eu selecionei "selected_group" com "FOR - 2011.1"
    Então eu deverei ver "Conteúdo"
        Quando eu clicar no link "Conteúdo"
    Então eu deverei ver o link "Material de Apoio"
        Quando eu clicar no link "Material de Apoio"
            Então eu deverei ver "AULAS"
            E eu deverei ver o link "1.jpg"