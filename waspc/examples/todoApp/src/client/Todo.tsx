import React, { useState, FormEventHandler, ChangeEventHandler } from 'react'
import { Link } from 'react-router-dom'

import { useQuery } from '@wasp/queries'
import { OptimisticUpdateDefinition, useAction } from '@wasp/actions'
import getTasks from '@wasp/queries/getTasks.js'
import createTask from '@wasp/actions/createTask.js'
import updateTaskIsDone from '@wasp/actions/updateTaskIsDone.js'
import deleteCompletedTasks from '@wasp/actions/deleteCompletedTasks.js'
import toggleAllTasks from '@wasp/actions/toggleAllTasks.js'
import { Task } from '@wasp/entities'

type GetTasksError = { message: string }

type NonEmptyArray<T> = [T, ...T[]]

function areThereAnyTasks(tasks: Task[] | undefined): tasks is NonEmptyArray<Task> {
  return !!(tasks && tasks.length > 0)
}

const Todo = () => {
  const { data: tasks, isError, error: tasksError } = useQuery<{}, Task[], GetTasksError>(getTasks)

  const TasksError = () => {
    return <div>{'Error during fetching tasks: ' + (tasksError?.message || '')}</div>
  }

  return (
    <div className='flex justify-center'>
      <div className='w-3/6 shadow-md rounded p-6'>
        <h1>Todos</h1>

        <div className='flex justify-start'>
          <ToggleAllTasksButton disabled={!areThereAnyTasks(tasks)} />
          <NewTaskForm />
        </div>

        {isError && <TasksError />}

        {areThereAnyTasks(tasks) && (
          <>
            <Tasks tasks={tasks} />

            <Footer tasks={tasks} />
          </>
        )}
      </div>
    </div>
  )
}

const Footer = ({ tasks }: { tasks: NonEmptyArray<Task> }) => {
  const numCompletedTasks = tasks.filter(t => t.isDone).length
  const numUncompletedTasks = tasks.filter(t => !t.isDone).length

  const handleDeleteCompletedTasks = async () => {
    try {
      await deleteCompletedTasks()
    } catch (err) {
      console.log(err)
    }
  }

  return (
    <div className='flex justify-between'>
      <div>
        {numUncompletedTasks} items left
      </div>

      <div>
        <button
          className={'btn btn-red ' + (numCompletedTasks > 0 ? '' : 'hidden')}
          onClick={handleDeleteCompletedTasks}
        >
          Delete completed
        </button>
      </div>
    </div>
  )
}

const Tasks = ({ tasks }: { tasks: NonEmptyArray<Task> }) => {
  return (
    <div>
      <table className='border-separate border-spacing-2'>
        <tbody>
          {tasks.map((task, idx) => <TaskView task={task} key={idx} />)}
        </tbody>
      </table>
    </div>
  )
}

type UpdateTaskIsDonePayload = Pick<Task, "id" | "isDone">

const TaskView = ({ task }: { task: Task }) => {
  const updateTaskIsDoneOptimistically = useAction(updateTaskIsDone, {
    optimisticUpdates: [{
      getQuerySpecifier: () => [getTasks],
      updateQuery: (updatedTask, oldTasks) => {
        if (oldTasks === undefined) {
          // cache is empty
          return [{ ...task, ...updatedTask }];
        } else {
          return oldTasks.map(task => task.id === updatedTask.id ? { ...task, ...updatedTask } : task)
        }
      }
    } as OptimisticUpdateDefinition<UpdateTaskIsDonePayload, Task[]>]
  });
  const handleTaskIsDoneChange: ChangeEventHandler<HTMLInputElement> = async (event) => {
    const id = parseInt(event.target.id)
    const isDone = event.target.checked

    try {
      await updateTaskIsDoneOptimistically({ id, isDone })
    } catch (err) {
      console.log(err)
    }
  }

  return (
    <tr>
      <td>
        <input
          type='checkbox'
          id={String(task.id)}
          checked={task.isDone}
          onChange={handleTaskIsDoneChange}
          color='default'
        />
      </td>
      <td>
        <Link to={`/task/${task.id}`}> {task.description} </Link>
      </td>
    </tr>
  )
}

const NewTaskForm = () => {
  const defaultDescription = ''
  const [description, setDescription] = useState(defaultDescription)

  const createNewTask = async (description: Task['description']) => {
    const task = { isDone: false, description }
    await createTask(task)
  }

  const handleNewTaskSubmit: FormEventHandler<HTMLFormElement> = async (event) => {
    event.preventDefault()
    try {
      await createNewTask(description)
      setDescription(defaultDescription)
    } catch (err) {
      console.log(err)
    }
  }

  return (
    <form onSubmit={handleNewTaskSubmit} className='content-start'>
      <input
        type='text'
        placeholder='Enter task'
        value={description}
        onChange={e => setDescription(e.target.value)}
      />
      <button className='btn btn-blue'>
        Create new task
      </button>
    </form>
  )
}

const ToggleAllTasksButton = ({ disabled }: { disabled: boolean }) => {
  const handleToggleAllTasks = async () => {
    try {
      await toggleAllTasks()
    } catch (err) {
      console.log(err)
    }
  }

  return (
    <button
      className='btn btn-blue'
      disabled={disabled}
      onClick={handleToggleAllTasks}
    >
      ✓
    </button>
  )
}

export default Todo
