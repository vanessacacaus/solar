class MessagesController < ApplicationController
  include FilesHelper
  include MessagesHelper

  before_filter :prepare_for_group_selection, only: [:index]

  ## [inbox, outbox, trashbox]
  def index
    allocation_tag_id = active_tab[:url][:allocation_tag_id]
    @show_system_label = allocation_tag_id.nil?
    @box = params[:box] || "inbox"

    @unreads = Message.user_inbox(current_user.id, allocation_tag_id, true).count

    @messages = Message.send("user_#{@box}", current_user.id, allocation_tag_id)
                        .paginate(page: params[:page] || 1, per_page: Rails.application.config.items_per_page)
                        .order("created_at DESC")
  end

  def new
    @message = Message.new
    @message.files.build

    @allocation_tag_id = active_tab[:url][:allocation_tag_id]
    @unreads = Message.user_inbox(current_user.id, @allocation_tag_id, true).count
    @contacts = user_contacts
  end

  def show
    @message = Message.find(params[:id])
    change_message_status(@message.id, "read", @box = params[:box] || "inbox")
  end

  def reply
    @original = Message.find(params[:id])
    raise CanCan::AccessDenied unless @original.user_has_permission?(current_user.id)

    @allocation_tag_id = active_tab[:url][:allocation_tag_id]
    @unreads = Message.user_inbox(current_user.id, @allocation_tag_id, true).count

    @message = Message.new subject: @original.subject
    @message.files.build

    # colocar essa parte em um template/helper?
    @message.content = %{
      <br/><br/>----------------------------------------<br/>
      #{t(:from, scope: [:messages, :show])} #{@original.sent_by.to_msg[:resume]}<br/>
      #{t(:date, scope: [:messages, :show])} #{l(@original.created_at, format: :clock)}<br/>
      #{t(:subject, scope: [:messages, :show])} #{@original.subject}<br/>
      #{t(:to, scope: [:messages, :show])} #{@original.users.map(&:to_msg).map{ |c| c[:resume] }.join(',')}<br/>
      #{@original.content}
    }

    @contacts = user_contacts
    @files = @original.files

    @reply_to = []
    case params[:type]
      when "reply"
        @reply_to = [@original.sent_by.to_msg]
        @message.subject = "#{t(:reply, scope: [:messages, :subject])} #{@message.subject}"
      when "reply_all"
        @reply_to = @original.users.uniq.map(&:to_msg)
        @message.subject = "#{t(:reply, scope: [:messages, :subject])} #{@message.subject}"
      when "forward"
        # sem contato default
        @message.subject = "#{t(:forward, scope: [:messages, :subject])} #{@message.subject}"
    end
  end

  def create
    @allocation_tag_id = active_tab[:url][:allocation_tag_id]
    params[:message][:allocation_tag_id] = @allocation_tag_id if @allocation_tag_id
    contacts = params[:message].delete(:contacts).split(",")

    # é uma resposta
    if params[:message][:original].present?
      @original = Message.find(params[:message].delete(:original)) # precisa para a view de new, caso algum problema aconteca
      original_files = @original.files.where(message_files: {id: params[:message].delete(:original_files)})
    end

    begin
      Message.transaction do
        ## msg ##

        @message = Message.new(params[:message], without_validation: true)

        ## users ##

        @message.user_messages.build(user: current_user, status: Message_Filter_Sender)
        (users = User.where(id: contacts)).each do |user|
          @message.user_messages.build(user: user, status: Message_Filter_Receiver)
        end

        ## files ##

        @message.files << original_files if original_files and not original_files.empty?

        @message.save!

        ## email ##

        system_label = not(@allocation_tag_id.nil?)

        msg = %{
          <b>#{t(:mail_header, scope: :messages)} #{current_user.to_msg[:resume]}</b><br/>
          #{@message.labels(current_user.id, system_label) if system_label}<br/>
          ________________________________________________________________________<br/><br/>
          #{@message.content}
        }

        Thread.new do
          Mutex.new.synchronize do # utilizado para organizar/controlar o comportamento das threads
            Notifier.send_mail(users.map(&:email).join(","), @message.subject, msg, @message.files).deliver
          end
        end
      end

      redirect_to outbox_messages_path, notice: t(:mail_sent, scope: :messages)
    rescue => error
      @unreads = Message.user_inbox(current_user.id, @allocation_tag_id, true).count
      @contacts = user_contacts
      @message.files.build

      render :new
    end
  end

  ## [read, unread, trash, restore]
  def update
    begin
      Message.transaction do
        params[:id].split(',').map(&:to_i).each { |i| change_message_status(i, params[:new_status], params[:box]) }
      end
      render json: {success: true}
    rescue
      render json: {success: false}, status: :unprocessable_entity
    end
  end

  def count_unread
    render json: {
      unread: Message.user_inbox(current_user.id, active_tab[:url][:allocation_tag_id], true).count
    }
  end

  def download_files
    file = MessageFile.find(params[:file_id])
    raise CanCan::AccessDenied unless file.message.user_has_permission?(current_user.id)

    download_file(inbox_messages_path, file.attachment.path, file.attachment_file_name)
  end

  private

    def user_contacts
      contacts = []
      # mudar para considerar apenas as allocation_tags das ofertas correntes
      (current_user.allocations.map(&:allocation_tag).compact.uniq).each do |at, idx|
        uc = at.groups.first.curriculum_unit
        contacts << {
          id: uc.id,
          curriculum_unit: uc.name,
          contacts: at.users.map(&:to_msg)
        }
      end
      contacts
    end
end
