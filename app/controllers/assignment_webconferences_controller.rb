class AssignmentWebconferencesController < ApplicationController

  include SysLog::Actions
  include AssignmentsHelper
  include Bbb

  before_filter :set_current_user, except: [:edit, :show]
  before_filter :get_ac, only: :new

  before_filter only: [:edit, :update, :destroy, :remove_record, :show] do |controller|
    @assignment_webconference = AssignmentWebconference.find(params[:id])
  end

  layout false

  def new
    group           = GroupAssignment.by_user_id(current_user.id, @ac.id)
    sent_assignment = SentAssignment.where(user_id: (group.nil? ? current_user.id : nil), group_assignment_id: group.try(:id), academic_allocation_id: @ac.id).first_or_create
    @assignment_webconference = AssignmentWebconference.new sent_assignment_id: sent_assignment.id
  end

  def create
    verify_owner!(assignment_webconference_params)

    @assignment_webconference = AssignmentWebconference.new assignment_webconference_params
    @assignment_webconference.save!
      
    render partial: 'webconference', locals: { webconference: @assignment_webconference }
  rescue CanCan::AccessDenied
    render json: { success: false, alert: t(:no_permission) }, status: :unauthorized
  rescue ActiveRecord::AssociationTypeMismatch
      render json: { success: false, alert: t(:not_associated) }, status: :unprocessable_entity
  rescue => error
    if @assignment_webconference.errors.any?
      render :new
    else
      render_json_error(error, 'assignment_webconferences.error')
    end
  end

  def edit
  end

  def update
    owner(assignment_webconference_params)
    @assignment_webconference.update_attributes! assignment_webconference_params

    render partial: 'webconference', locals: { webconference: @assignment_webconference }
  rescue CanCan::AccessDenied
    render json: { success: false, alert: t(:no_permission) }, status: :unauthorized
  rescue ActiveRecord::AssociationTypeMismatch
      render json: { success: false, alert: t(:not_associated) }, status: :unprocessable_entity
  rescue => error
    if @assignment_webconference.errors.any?
      render :edit
    else
      render_json_error(error, 'assignment_webconferences.error')
    end
  end

  def destroy
    @assignment_webconference.destroy
    render json: { success: true, notice: t('assignment_webconferences.success.removed') }
  rescue => error
    render_json_error(error, 'assignment_webconferences.error')
  end

  def remove_record
    verify_owner!(@assignment_webconference)

    @assignment_webconference.can_remove_records?

    if params.include?(:recordID)
      @assignment_webconference.remove_record(params[:recordID])
      save_log(@assignment_webconference)
    else
      @assignment_webconference.remove_records
      save_log(@assignment_webconference)
    end

    render json: { success: true, notice: t('assignment_webconferences.success.record') }
  rescue => error
    render_json_error(error, 'assignment_webconferences.error')
  end

  def show
    verify_owner!(@assignment_webconference)
    render partial: 'webconference', locals: { webconference: @assignment_webconference }
  rescue CanCan::AccessDenied
    render json: { success: false, alert: t(:no_permission) }, status: :unauthorized
  end

  def get_record
    @assignment_webconference = AssignmentWebconference.find(params[:id])
    sent_assignment          = SentAssignment.find(params[:sent_assignment_id])
    at_id                    = active_tab[:url][:allocation_tag_id]
    verify_owner_or_responsible!(at_id, sent_assignment)

    raise CanCan::AccessDenied if current_user.is_researcher?(AllocationTag.find(at_id).related)

    raise 'offline'          unless bbb_online?
    raise 'no_record'        unless @assignment_webconference.is_recorded? && @assignment_webconference.over?
    raise 'still_processing' unless @assignment_webconference.is_over?

    begin
      verify_owner!(@assignment_webconference)
      @can_remove_record = true
    rescue
      @can_remove_record = false
    end

    @recordings = @assignment_webconference.recordings([], (at_id.class == Array ? nil : at_id))
  rescue CanCan::AccessDenied
    render json: { success: false, alert: t(:no_permission) }, status: :unprocessable_entity
  rescue URI::InvalidURIError
    render json: { success: false, alert: t('webconferences.list.removed_record') }, status: :unprocessable_entity
  rescue => error
    render_json_error(error, 'webconferences.error')
  end

  private

    def save_log(assignment_webconference)
      log = if params.include?(:recordID)
        { description: "assignment_webconference: #{@assignment_webconference.id}  removing recording #{params[:recordID]} by user #{current_user.id}" }
      else
        { description: "assignment_webconference: #{@assignment_webconference.id}  removing all recordings by user #{current_user.id}" }
      end

      LogAction.create({ log_type: LogAction::TYPE[request_method(request.request_method)], user_id: current_user.id, ip: request.remote_ip, allocation_tag_id: assignment_webconference.allocation_tag.id, academic_allocation_id: assignment_webconference.academic_allocation.id }.merge!(log))
    end

    def assignment_webconference_params
      params.require(:assignment_webconference).permit(:sent_assignment_id, :title, :initial_time, :duration, :is_recorded)
    end

end
