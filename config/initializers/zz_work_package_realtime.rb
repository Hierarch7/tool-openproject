# frozen_string_literal: true

# Живое обновление задач без перезагрузки страницы.
#
# Ядро OpenProject не имеет ни ActionCable-каналов, ни опроса для таблицы задач: статус,
# изменённый другим пользователем, доезжает до чужой вкладки только с перезагрузкой. Здесь
# мы ловим создание и правку журнала и рассылаем сигнал в WorkPackagesChannel.
#
# Событие берём именно журнальное, а не AGGREGATED_WORK_PACKAGE_JOURNAL_READY, на котором
# сидит модуль вебхуков: агрегированное приходит отложенной фоновой задачей через окно
# агрегации (по умолчанию 5 минут), что для «без перезагрузки» бессмысленно.
#
# JOURNAL_CREATED шлётся из after_save, то есть внутри транзакции. Вещать оттуда нельзя:
# клиент в ответ на сигнал перезапрашивает задачу и успел бы прочитать её до коммита, получив
# старое значение. after_all_transactions_commit откладывает отправку до внешнего коммита,
# а вне транзакции выполняет блок сразу.
#
# Ошибка здесь не должна ронять сохранение задачи: подписчики ActiveSupport::Notifications
# выполняются в стеке вызывающего, так что исключение прервало бы работу с журналом.
Rails.application.config.after_initialize do
  broadcast = lambda do |payload|
    work_package = payload[:journal]&.journable
    next unless work_package.is_a?(WorkPackage) && work_package.project_id

    ActiveRecord.after_all_transactions_commit do
      WorkPackagesChannel.broadcast_to(work_package.project, id: work_package.id)
    rescue StandardError => e
      Rails.logger.error { "Failed to broadcast work package ##{work_package.id}: #{e.message}" }
    end
  end

  OpenProject::Notifications.subscribe(OpenProject::Events::JOURNAL_CREATED, &broadcast)
  OpenProject::Notifications.subscribe(OpenProject::Events::JOURNAL_UPDATED, &broadcast)
end
