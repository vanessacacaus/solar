Capybara.add_selector(:element) do
  xpath { |locator| "//*[normalize-space(text())=#{XPath::Expression::StringLiteral.new(locator)}]" }
end

Quando 'eu clicar no item "$locator" de id "$id"' do |locator, id|
  find(:xpath, XPath::HTML.content(locator)).click
  page.execute_script("toggle_div('div_group_"+id+"')")
end

Quando 'eu clicar no grupo "$grupo_id"' do |grupo_id|
	page.execute_script("clickOnGroup('"+grupo_id+"')")
end

Quando 'eu selecionar o usuario de id "$id"' do |id|
	check('students__'+id)
end

Entao 'eu deverei ver os alunos do grupo com id "$id" selecionados' do |id|
	find('#students__'+id).should be_checked
end

E 'eu clicar em "$resposta_confirm" no popup' do |resposta_confirm|
	a = page.driver.browser.switch_to.alert
	if resposta_confirm == "Ok"
  		a.accept
	else
  		a.dismiss
	end
	sleep 2
end

Entao 'eu deverei estar em "$nome_pagina"' do |nome_pagina|
	current_path.should == path_to(nome_pagina)
end

Entao 'eu nao deverei ver o elemento de id "$id"' do |id|
	page.should_not have_css('#'+id)
end

Entao 'eu deverei ver o elemento de id "$id"' do |id|
	page.should have_css('#'+id)
end

Entao 'eu nao deverei ver o botao "$botao"' do |botao|
  	find_button(botao).should be_nil
end

Quando 'eu clicar no botao de importacao de id "$id"' do |id|
	page.should have_css('#import_to_'+id)
	page.execute_script("$('#import_to_"+id+"').click()")
	page.execute_script("showImportGroupBox('/group_assignments/import_groups_page/1?assignment_id="+id+"', '');")
end

Entao 'eu deverei aguardar "$segundos" segundos' do |segundos|
	sleep segundos.to_i
end
