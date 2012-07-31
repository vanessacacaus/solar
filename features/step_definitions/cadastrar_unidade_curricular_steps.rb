Entao /^eu deverei ver a linha de Unidade Curricular$/ do |tabela|
	tabela.hashes.each do |linha|
		xpath = "//table/tbody/tr[ child::td[contains(., '#{linha[:Codigo]}')] and child::td[contains(., '#{linha[:Nome]}')] and child::td[contains(., '#{linha[:Categoria]}')] ]"
		page.should have_xpath(xpath)
	end
end

Entao /^eu nao deverei ver a linha de Unidade Curricular$/ do |tabela| 
	tabela.hashes.each do |linha|
		xpath = "//table/tbody/tr[ child::td[contains(., '#{linha[:Codigo]}')] and child::td[contains(., '#{linha[:Nome]}')] and child::td[contains(., '#{linha[:Categoria]}')] ]"
		page.should have_no_xpath(xpath)
	end
end

#Quando /^eu clicar no botão "([^"]*)" da linha que contem o item "([^"]*)"$/ da tabela do |link, texto|
Quando /^eu clicar no botao "(.*?)" da linha que contem o item "(.*?)" da tabela$/ do |link, texto|
  xpath = "//table/tbody/tr[ child::td[contains(.,'#{texto}')] ]"
  within(:xpath, xpath) do
    find_button("#{link}").click
  end
end