import React, { useContext, useEffect, useState } from 'react'
import Modal from 'react-bootstrap/lib/Modal'
import LoadingSpinner from '~/lib/LoadingSpinner'
import UserProvider, { UserContext } from '~/providers/UserProvider'
import { fetchUserSavedViews, createUserSavedView, updateUserSavedView, deleteUserSavedView } from '~/lib/scp-api'

export default function SavedViews() {
  const userState = useContext(UserContext)
  const [savedViews, setSavedViews] = useState([])

  async function loadSavedViews() {
    const savedViewsResponse = await fetchUserSavedViews()
    setSavedViews(savedViewsResponse)
  }
}
