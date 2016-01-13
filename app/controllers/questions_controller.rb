class QuestionsController < ApplicationController

  include SysLog::Actions

  before_filter :set_current_user, only: [:destroy, :change_status, :verify_owners, :copy]

  layout false, except: :index

  def index
    authorize! :index, Question
    @questions = Question.get_all(current_user.id, params[:search] || {}, params[:verify_privacy])
    render partial: 'questions/questions' unless params[:search].nil?
  end

  def new
    @question = Question.new
    @question.question_images.build
    @question.question_labels.build
    @question.question_items.build
  end

  def create
    authorize! :create, Question
    @question         = Question.new question_params
    @question.user_id = current_user.id

    if @question.save
      render partial: 'question', locals: { question: @question }
    else
      render json: { success: false, alert: @question.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end

  rescue CanCan::AccessDenied
    render json: { success: false, alert: t(:no_permission) }, status: :unauthorized
  rescue => error
    render_json_error(error, 'questions.error')
  end

  def change_status
    authorize! :change_status, Question
    ids = params[:id].split(',') rescue [params[:id]]
    @questions = Question.where(id: ids)
    ActiveRecord::Base.transaction do
      @questions.each do |question|
        question.can_change_status?
        question.update_attributes status: (params[:status].nil? ? !question.status : params[:status])
      end
    end

    render json: { success: true, notice: t('questions.success.change_status') }
  rescue CanCan::AccessDenied
    render json: { success: false, alert: t(:no_permission) }, status: :unauthorized
  rescue => error
    render_json_error(error, 'questions.error')
  end

  def edit
    @question = Question.find(params[:id])
    @question.question_images.build
    @question.question_labels.build
    @question.question_items.build
  end

  def update
    authorize! :update, Question
    @question         = Question.find params[:id]

    if @question.update_attributes question_params
      render partial: 'question', locals: { question: @question }
    else
      render json: { success: false, alert: @question.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end

  rescue CanCan::AccessDenied
    render json: { success: false, alert: t(:no_permission) }, status: :unauthorized
  rescue => error
    render_json_error(error, 'questions.error')
  end

  def destroy
    authorize! :destroy, Question
    ActiveRecord::Base.transaction do
      Question.where(id: params[:id].split(',')).each do |question|
        question.destroy
      end
    end
    render json: { success: true, notice: t('questions.success.deleted') }
  rescue CanCan::AccessDenied
    render json: { success: false, alert: t(:no_permission) }, status: :unauthorized
  rescue => error
    render_json_error(error, 'questions.error')
  end

  def show
    authorize :show, Question
    @question = Question.find params[:id]
    @question.can_see?
  rescue CanCan::AccessDenied
    render json: { success: false, alert: t(:no_permission) }, status: :unauthorized
  rescue => error
    render_json_error(error, 'questions.error')
  end

  def verify_owners
    question = Question.find params[:id]
    question.can_change? if params[:update]
    question.can_copy?   if params[:copy]
    render json: { success: true }
  rescue => error
    render_json_error(error, 'questions.error')
  end

  def copy
    question  = Question.find params[:id]
    @question = Question.copy(question, current_user.id)

    log(question, "question: #{question.id} [copy], #{question.log_description}", LogAction::TYPE[:create]) rescue nil

    @question.question_images.build
    @question.question_labels.build
    @question.question_items.build

    render :edit
  end

  private

  def question_params
    params.require(:question).permit(:enunciation, :type_question, 
      question_items_attributes: [:id, :item_image, :value, :description, :_destroy, :comment, :img_alt],
      question_images_attributes: [:id, :image, :legend, :img_alt, :_destroy],
      question_labels_attributes: [:id, :name, :_destroy])
  end

  def params_to_log
    { user_id: current_user.id, ip: request.remote_ip }
  end

  def log(object, message, type=LogAction::TYPE[:update])
    LogAction.create(params_to_log.merge!(description: message, log_type: type))
  end

end
