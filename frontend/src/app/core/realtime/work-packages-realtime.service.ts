import { Injectable, inject } from '@angular/core';
import { createConsumer } from '@rails/actioncable';
import type { Consumer, Subscription } from '@rails/actioncable';

import { CurrentProjectService } from 'core-app/core/current-project/current-project.service';
import { ApiV3Service } from 'core-app/core/apiv3/api-v3.service';
import { debugLog } from 'core-app/shared/helpers/debug_output';

interface WorkPackageChangedMessage {
  id:number;
}

/** Window over which incoming ids are collected before one batched reload goes out. */
const COALESCE_MS = 250;

/**
 * Keeps open views in sync with changes other people make.
 *
 * The server only tells us *which* work package changed, never what it now says: a project
 * channel reaches every subscriber at once, so a payload carrying attributes would hand them
 * out without regard for permissions. We answer a message by reloading through the regular
 * API, which applies the usual authorisation — anything the viewer may not see simply does
 * not come back.
 */
@Injectable({ providedIn: 'root' })
export class WorkPackagesRealtimeService {
  private currentProject = inject(CurrentProjectService);

  private apiV3Service = inject(ApiV3Service);

  private consumer:Consumer|null = null;

  private subscription:Subscription|null = null;

  private subscribedProjectId:string|null = null;

  private pendingIds = new Set<string>();

  private flushTimer:ReturnType<typeof setTimeout>|null = null;

  /**
   * Runs on every turbo render, so it stays a no-op while the project is unchanged.
   */
  public initialize():void {
    const projectId = this.currentProject.id;

    if (projectId === this.subscribedProjectId) {
      return;
    }

    this.disconnect();

    if (!projectId) {
      return;
    }

    this.subscribedProjectId = projectId;
    this.subscription = this
      .cableConsumer()
      .subscriptions
      .create(
        { channel: 'WorkPackagesChannel', project_id: projectId },
        { received: (data:WorkPackageChangedMessage) => this.enqueue(data) },
      );
  }

  public disconnect():void {
    this.subscription?.unsubscribe();
    this.subscription = null;
    this.subscribedProjectId = null;

    if (this.flushTimer) {
      clearTimeout(this.flushTimer);
      this.flushTimer = null;
    }
    this.pendingIds.clear();
  }

  /**
   * Ids are collected rather than fetched one by one. A single edit can journal a whole
   * subtree — a moved parent rewrites the dates of every descendant — and without this every
   * one of those would be a separate request, from every tab watching the project at once.
   */
  private enqueue(data:WorkPackageChangedMessage):void {
    const id = data?.id?.toString();

    if (!id) {
      return;
    }

    this.pendingIds.add(id);
    this.flushTimer ??= setTimeout(() => this.flush(), COALESCE_MS);
  }

  private flush():void {
    this.flushTimer = null;

    const ids = Array.from(this.pendingIds);
    this.pendingIds.clear();

    if (ids.length === 0) {
      return;
    }

    // requireAll loads the whole batch in one collection request and writes each result into
    // the cache, which is what every open table row and single view is subscribed to.
    this
      .apiV3Service
      .work_packages
      .requireAll(ids)
      .catch((error:unknown) => debugLog(`Failed to reload work packages ${ids.join(', ')}: ${String(error)}`));
  }

  private cableConsumer():Consumer {
    this.consumer ??= createConsumer(`${window.appBasePath}/cable`);
    return this.consumer;
  }
}
