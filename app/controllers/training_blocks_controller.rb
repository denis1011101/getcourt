class TrainingBlocksController < ApplicationController
  before_action :set_training_block, only: %i[update destroy]

  def index
    @training_block = TrainingBlock.new
    @training_blocks = current_user.training_blocks.ordered
  end

  def create
    @training_block = current_user.training_blocks.new(training_block_params)

    if @training_block.save
      redirect_to training_blocks_path, notice: t("training_blocks.created")
    else
      @training_blocks = current_user.training_blocks.ordered
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @training_block.update(training_block_params)
      redirect_to training_blocks_path, notice: t("training_blocks.updated")
    else
      redirect_to training_blocks_path, alert: @training_block.errors.full_messages.to_sentence
    end
  end

  def destroy
    @training_block.destroy
    redirect_to training_blocks_path, notice: t("training_blocks.destroyed")
  end

  private

  # Правку и удаление пускаем только по своей библиотеке.
  def set_training_block
    @training_block = current_user.training_blocks.find(params[:id])
  end

  def training_block_params
    params.require(:training_block).permit(:title, :description, :duration_minutes, :shared, :diagram)
  end
end
