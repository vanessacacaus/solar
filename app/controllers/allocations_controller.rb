class AllocationsController < ApplicationController
  include AllocationsHelper

  layout false, except: [:index]

  authorize_resource except: [:destroy, :designates, :create_designation, :activate, :deactivate]

  # GET /allocations/designates
  # GET /allocations/designates.json
  def designates
    if (not params.include?(:admin) or params.include?(:allocation_tags_ids))
      @allocation_tags_ids  = params.include?(:allocation_tags_ids) ? params[:allocation_tags_ids].split(" ").flatten : [] 
    elsif params[:groups_id].blank?
      if params.include?(:semester_id) and (not params[:semester_id] == "")
        @allocation_tags_ids = [Offer.where(semester_id: params[:semester_id], curriculum_unit_id: params[:curriculum_unit_id], course_id: params[:course_id]).first.allocation_tag.id]
      elsif params.include?(:curriculum_unit_id) and (not params[:curriculum_unit_id] == "")
        @allocation_tags_ids = [CurriculumUnit.find(params[:curriculum_unit_id]).allocation_tag.id]
      elsif params.include?(:course_id) and (not params[:course_id] == "")
        @allocation_tags_ids = [Course.find(params[:course_id]).allocation_tag.id]
      end
    else
      @allocation_tags_ids = AllocationTag.where(group_id: params[:groups_id]).map(&:id)
    end

    begin    
      @admin = true if params.include?(:admin)
      
      if @admin 
        authorize! :create_designation, Allocation
      else
        authorize! :create_designation, Allocation, on: @allocation_tags_ids.flatten
      end

      level        = (params[:permissions] != "all" and (not params.include?(:admin))) ? "responsible" : nil
      level_search = level.nil? ? ("not(profiles.types & #{Profile_Type_Basic})::boolean") : ("(profiles.types & #{Profile_Type_Class_Responsible})::boolean")
      
      @allocations = Allocation.all(
        joins: [:profile, :user], 
        conditions: ["#{level_search} and allocation_tag_id IN (#{@allocation_tags_ids.join(",")}) "],
        order: ["users.name", "profiles.name"]) 
    rescue CanCan::AccessDenied
      render json: {success: false, alert: t(:no_permission)}, status: :unprocessable_entity
    rescue ActiveRecord::AssociationTypeMismatch
      render json: {success: false, alert: t(:not_associated)}, status: :unprocessable_entity
    rescue 
      render nothing: true, status: :unprocessable_entity
    end
  end

  # Método, chamado por ajax, para buscar usuários para alocação
  def search_users
    text                 = URI.unescape(params[:user])
    @text_search         = text
    @allocation_tags_ids = params[:allocation_tags_ids].split(" ")
    @users               = User.where("lower(name) ~ '#{text.downcase}'")
    @admin               = params[:admin]
  end

  # GET /allocations/enrollments
  # GET /allocations/enrollments.json
  def index
    @allocations = []
    groups = groups_that_user_have_permission.map(&:id)

    unless groups.empty?
      # params['status'] = 0 unless params.include?('status') # para listar somente usuarios pendentes
      p = params.select { |k, v| ['offer_id', 'group_id', 'status'].include?(k) }
      p['group_id'] = (params.include?('group_id') and groups.include?(params['group_id'].to_i)) ? [params['group_id']] : groups.flatten.compact.uniq

      @allocations  = Allocation.enrollments(p)
    end
  end

  # GET /allocations/1
  # GET /allocations/1.json
  def show
    @allocation = Allocation.find(params[:id])
    respond_to do |format|
      format.html
      format.json { render json: @allocation }
    end
  end

  # GET /allocations/1/edit
  def edit
    @allocation   = Allocation.find(params[:id])
    @status_hash  = status_hash_of_allocation(@allocation.status)
    @change_group = (not [Allocation_Cancelled, Allocation_Rejected].include?(@allocation.status))

    # transicao entre grupos apenas da mesma oferta
    @groups       = @change_group ? Group.where(:offer_id => @allocation.group.offer_id) : @allocation.group
  end
  
  # Usado na matrícula
  def create
    profile, status = Profile.student_profile, Allocation_Pending
    allocation_tag  = AllocationTag.find(params[:allocation_tag_id])

    if profile == Profile.student_profile
      allocation_tag = AllocationTag.find(params[:allocation_tag_id])
      offer   = allocation_tag.offer || allocation_tag.group.offer
      ok      = (offer.enrollment_start_date.to_date..(offer.enrollment_end_date.try(:to_date) || offer.end_date.to_date)).include?(Date.today)
    end

    ok      = allocate(params[:allocation_tag_id], params[:user_id], profile, status) if ok or ok.nil?
    message = ok ? ['notice', 'success'] : ['alert', 'error']
    respond_to do |format|
      format.html { redirect_to(enrollments_url, message.first.to_sym => t(:enrollm_request, scope: [:allocations, message.last.to_sym])) }
    end
  end

  # Usado na alocacao de usuarios
  def create_designation
    allocation_tags_ids = case
    when (not params[:groups].nil?)
      [Group.where(id: params[:groups]).map(&:allocation_tag).map(&:id)]
    when (not(params[:semester].blank?) and not(params[:curriculum_unit].blank?) and not(params[:course].blank?))
      [Offer.where(semester_id: params[:semester], curriculum_unit_id: params[:curriculum_unit], course_id: params[:course]).first.allocation_tag.id]
    when (not params[:curriculum_unit].blank?)
      [CurriculumUnit.find(params[:curriculum_unit]).allocation_tag.id]
    when (not params[:course].blank?)
      [Course.find(params[:course]).allocation_tag.id]
    when params.include?(:allocation_tags_ids)
      params[:allocation_tags_ids].split(" ")
    else
      nil
    end

    authorize! :create_designation, Allocation if params[:admin] 
    authorize! :create_designation, Allocation, on: allocation_tags_ids.flatten unless params[:admin] or params.include?(:request)

    profile = params.include?(:profile) ? params[:profile] : Profile.student_profile
    status  = params.include?(:status) ? params[:status]  : Allocation_Pending
    user    = (params.include?(:user_id) and not(params.include?(:request))) ? params[:user_id] : current_user.id
    raise t("allocations.error.student_or_basic") if profile == Profile.student_profile or (not(profile.blank?) and Profile.find(profile).has_type?(Profile_Type_Basic))
    raise t("allocations.error.profile") if params[:profile].blank?
    ok = allocate(allocation_tags_ids, user, profile, status)

    unless params.include?(:request)
      render :designates, status: (ok ? 200 : :unprocessable_entity)
    else
      case ok
        when nil; render json: {success: true, message: t("allocations.warning.already_active"), type: "warning"}
        when true; render json: {success: true, message: t("allocations.success.requested"), type: "notice"}
        when false; render json: {success: false, alert: t("allocations.error.not_allocated")}, status: :unprocessable_entity
      end
    end
  rescue => error
    render json: {success: false, alert: error.message}, status: :unprocessable_entity
  end

  # PUT /allocations/1
  # PUT /allocations/1.json
  def update
    # authorize! :update, Allocation #.find(params[:id]) [authorize pelo authorize_resources]

    mutex = Mutex.new # utilizado para organizar/controlar o comportamento das threads
    allocations = Allocation.where(id: params[:id].split(","))
    allocation_tag_id = (params.include?(:allocation) and params[:allocation].include?(:group_id)) ? Group.find(params[:allocation][:group_id]).allocation_tag.id : nil
    
    # verifica se existe mudanca de turma
      # se sim, todas as alocacoes serao canceladas e serao criadas novas com a nova turma
      # se não, somente o status das alocacoes serao modificados

    error = false
    begin
      ActiveRecord::Base.transaction do
        # mudanca de turma, nao existe chamada multipla para esta funcionalidade
        if ((not params.include?(:multiple)) and (not allocation_tag_id.nil?) and (allocation_tag_id != allocations.first.allocation_tag_id))
          # criando novas alocacoes e cancelando as antigas
          allocation = allocations.first
          allocation.update_attribute(:status, Allocation_Cancelled) # cancelando a anterior
          @allocation = Allocation.create!(allocation.attributes.merge({allocation_tag_id: allocation_tag_id, status: params[:allocation][:status]}))

          Thread.new do
            mutex.synchronize {
              Notifier.enrollment_accepted(@allocation.user.email, @allocation.group.code_semester).deliver if params[:allocation][:status].to_i == Allocation_Activated.to_i
            }
          end
        else # sem mudanca de turma

          new_status  = params.include?(:enroll) ? Allocation_Activated.to_i : ((params.include?(:allocation) and params[:allocation].include?(:status)) ? params[:allocation][:status] : 0)

          allocations.each do |al|
            changed_status_to_accepted = ((al.status.to_i != Allocation_Activated.to_i) and (new_status.to_i == Allocation_Activated.to_i))
            al.update_attribute(:status, new_status)

            Thread.new do
              mutex.synchronize {
                Notifier.enrollment_accepted(al.user.email, al.group.code_semester).deliver if changed_status_to_accepted
              }
            end
          end # allocations

          @allocation = allocations.first
        end # if
      end # transaction

      flash[:notice] = t(:enrollment_successful_update, scope: [:allocations, :manage])
    rescue ActiveRecord::RecordNotUnique
      error     = true
      msg_error = t(:student_already_in_group, scope: [:allocations, :error])
    rescue 
      error     = true
      msg_error = t(:enrollment_unsuccessful_update, scope: [:allocations, :manage])
    end

    if error
      render :js => "javascript:flash_message('#{msg_error}', 'alert');"
    else
      respond_to do |format|
        format.html { render action: :show }
        format.json { render json: {status: "ok"}  }
      end
    end
  end

  # DELETE /allocations/1/cancel
  # DELETE /allocations/1/cancel_request
  def destroy
    authorize! :cancel, Allocation if not params.include?(:type)
    authorize! :cancel_request, Allocation if params.include?(:type) and params[:type] == 'request'

    @allocation = Allocation.find(params[:id])

    begin
      error = false
      raise CanCan::AccessDenied if (@allocation.user_id != current_user.id and params[:type] == "request") or
        ((@allocation.profile_id == Profile.student_profile or @allocation.profile.has_type?(Profile_Type_Basic)) and params.include?(:profile))

      if params.include?(:type) and params[:type] == 'request' and @allocation.status == Allocation_Pending
        @allocation.destroy
        message = (params.include?(:profile) ? t("allocations.success.request_canceled") : t(:enrollm_request_cancel_message))
      else
        @allocation.update_attribute(:status, Allocation_Cancelled)
        message = (params.include?(:profile) ? t("allocations.success.profile_canceled") : t(:enrollm_cancelled_message))
      end
    rescue CanCan::AccessDenied
      error = true
      message = t(:no_permission)
    rescue Exception => e
      message = (params.include?(:profile) ? t("allocations.error.cancel_request") : t(:enrollm_not_cancelled_message))
      error   = true
    end

    respond_to do |format|
      unless error
        format.html { redirect_to(:back, notice: message) }
        format.json { render json: {success: :ok, notice: message} }
      else
        format.html { redirect_to(:back, alert: message) }
        format.json { render json: {success: false, alert: message}, status: :unprocessable_entity }
      end
    end
  end

  def deactivate
    @allocation  = Allocation.find(params[:id])
    @text_search = params[:text_search]

    begin 
      authorize! :deactivate, @allocation
      raise "error" unless @allocation.update_attribute(:status, Allocation_Cancelled)

      render json: {success: true}
    rescue
      render json: {success: false, alert: t(:not_deactivated, scope: [:allocations, :error])}, status: :unprocessable_entity
    end
  end

  def activate
    @allocation       = Allocation.find(params[:id])
    allocation_tag_id = @allocation.allocation_tag_id

    begin
      authorize! :activate, @allocation
      raise "error" unless @allocation.update_attribute(:status, Allocation_Activated)

      render json: {success: true}
    rescue
      render json: {success: false, alert: t(:not_activated, scope: [:allocations, :error])}, status: :unprocessable_entity
    end
  end  

  def reactivate
    @allocation = Allocation.find(params[:id])
    offer = @allocation.offer || @allocation.group.offer
    ok = (offer.enrollment_start_date.to_date..(offer.enrollment_end_date.try(:to_date) || offer.end_date.to_date)).include?(Date.today)

    respond_to do |format|
      if (ok and @allocation.update_attribute(:status, Allocation_Pending_Reactivate))
        format.html { redirect_to(enrollments_url, notice: t(:enrollm_request, :scope => [:allocations, :success])) }        
        format.json { head :ok }
      else
        format.html { redirect_to(enrollments_url, alert: t(:enrollm_request, :scope => [:allocations, :error])) }        
        format.json { head :error }
      end
    end
  end  

  private

    def groups_that_user_have_permission
      profiles = current_user.profiles_with_access_on("index", "allocations").map(&:id)
      groups = current_user.allocations.where(profile_id: profiles).where("allocation_tag_id IS NOT NULL").map {|a| a.allocation_tag.groups }.flatten.uniq
    end

    def status_hash_of_allocation(allocation_status)
      case allocation_status
        when Allocation_Pending, Allocation_Pending_Reactivate
          status_hash.select { |k,v| [allocation_status, Allocation_Activated, Allocation_Rejected].include?(k) }
        when Allocation_Activated
          status_hash.select { |k,v| [allocation_status, Allocation_Cancelled].include?(k) }
        when Allocation_Cancelled, Allocation_Rejected
          status_hash.select { |k,v| [allocation_status, Allocation_Activated].include?(k) }
      end
    end

    def allocate(allocation_tags_ids, user_id, profile, status)
      success = true
      [allocation_tags_ids].flatten.each do |allocation_tag_id|
        allocation = Allocation.where(allocation_tag_id: allocation_tag_id, user_id: user_id, profile_id: profile).first_or_initialize
        unless allocation.new_record? # existe alocação
          if allocation.status != Allocation_Activated # não ativa
            allocation.update_attribute(:status, Allocation_Pending_Reactivate)
          elsif [allocation_tags_ids].size == 1
            success = nil
          end
        else # não existe alocação
          allocation.status = status
          success = false unless allocation.save
        end
      end
    rescue => error
      success = false
    ensure
      return success
    end

end
