<div>
    <h1>Scheduled Task</h1>
    @if ($type === 'application')
        <livewire:project.application.heading :application="$resource" />
    @elseif ($type === 'service')
        <livewire:project.service.navbar :service="$resource" :parameters="$parameters" />
    @endif

    <form wire:submit="submit" class="w-full">
        <div class="flex flex-col gap-2 pb-4">
            <div class="flex items-end gap-2 pt-4">
                <h2>Scheduled Task</h2>
                <x-forms.button type="submit">
                    Save
                </x-forms.button>
                <x-new-modal isErrorButton buttonTitle="Delete Scheduled Task">
                    You will delete scheduled task <span class="font-bold text-warning">{{ $task->name }}</span>.
                </x-new-modal>
            </div>
        </div>
        <div class="flex w-full gap-2">
            <x-forms.input placeholder="Name" id="task.name" label="Name" required />
            <x-forms.input placeholder="php artisan schedule:run" id="task.command" label="Command" required />
            <x-forms.input placeholder="0 0 * * * or daily" id="task.frequency" label="Frequency" required />
            <x-forms.input placeholder="php" helper="You can leave it empty if your resource only have one container."
                id="task.container" label="Container name" />
        </div>
    </form>

    <div class="pt-4">
        <h3 class="py-4">Recent executions <span class="text-xs text-neutral-500">(click to check output)</span></h3>
        <livewire:project.shared.scheduled-task.executions key="{{ $task->id }}" selectedKey="" :executions="$task->executions->take(-20)" />
    </div>
</div>
